/**
 * @description       : Service class to handle Jira API interactions, processing Tasks, Bugs, Sub-tasks, and creating Epic/Story and Work Item records.
 * @author            : [Your Actual Name]
 * @group             : DevOps Integration
 * @last modified on  : 07-17-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
 */
public with sharing class JiraService {
    
    // Retrieve custom metadata configuration
    private static final Jira_Configuration__mdt CONFIG = getJiraConfiguration();

    /**
     * @description Retrieve Jira configuration from custom metadata
     * @return Jira_Configuration__mdt record
     */
    private static Jira_Configuration__mdt getJiraConfiguration() {
        try {
            Jira_Configuration__mdt config = [
                SELECT Jira_Base_URL__c, Jira_API_Endpoint__c, Request_Timeout__c, Max_Results__c,
                       Default_User_ID__c, Work_Item_Creation_Field__c, Issue_Type_Story__c,
                       Issue_Type_Subtask__c, Issue_Type_Epic__c, Issue_Type_Task__c,
                       Issue_Type_Bug__c, // Added to support Bug issue type
                       Parent_Status__c, Sub_Task_status__c, Assignee_Field__c, 
                       Error_Blank_Project_Key__c, Error_Project_Not_Found__c, 
                       Jira_Fields__c, Jira_User_Name__c, Jira_API_Token__c
                FROM Jira_Configuration__mdt
                WHERE DeveloperName = 'Default_Jira_Configuration'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return config;
        } catch (QueryException ex) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving Jira configuration: ' + ex.getMessage());
            throw new AuraHandledException('Jira configuration not found: ' + ex.getMessage());
        }
    }

    /**
     * @description Get Jira Base URL from configuration
     * @return Jira Base URL
     */
    @AuraEnabled
    public static String getJiraBaseUrl() {
        try {
            if (String.isBlank(CONFIG.Jira_Base_URL__c)) {
                throw new AuraHandledException('Jira Base URL is not configured');
            }
            return CONFIG.Jira_Base_URL__c;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving Jira Base URL: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving Jira Base URL: ' + e.getMessage());
        }
    }

    /**
     * @description Wrapper class for Jira API requests
     */
    public class JiraRequest {
        public String projectKey { get; set; }
        public String issueTypeId { get; set; }
        public String taskDescription { get; set; }
        public String taskSummary { get; set; }
        public String dueDate { get; set; }
    }
    
    /**
     * @description Response wrapper for Jira API calls
     */
    public class JiraResponse {
        public String id { get; set; }
        public String key { get; set; }
        public String self { get; set; }
        
        public JiraResponse parse(String jsonString) {
            return (JiraResponse) JSON.deserialize(jsonString, JiraResponse.class);
        }
    }
    
    /**
     * @description Wrapper for processing results
     */
    public class ProcessingResult {
        @AuraEnabled
        public Integer storiesCreated { get; set; }
        @AuraEnabled
        public Integer workItemsCreated { get; set; }
        @AuraEnabled
        public List<String> errors { get; set; }
        @AuraEnabled
        public List<String> storyIds { get; set; }

        public ProcessingResult() {
            this.storiesCreated = 0;
            this.workItemsCreated = 0;
            this.errors = new List<String>();
            this.storyIds = new List<String>();
        }
    }
    
    /**
     * @description Get all Tasks, Bugs, and Sub-tasks from Jira for a specific project using the API endpoint with pagination
     * @param projectKey The Jira project key
     * @return JSON response containing all issues
     */
    public static String getSubtasksForProject(String projectKey) {
        if (String.isBlank(projectKey)) {
            throw new IllegalArgumentException(CONFIG.Error_Blank_Project_Key__c);
        }
        
        List<Object> allIssues = new List<Object>();
        Integer startAt = 0;
        Integer total = 0;
        Http httpClient = new Http();
        
        do {
            HttpRequest request = buildJiraSubtaskRequest(projectKey, startAt);
            
            try {
                HttpResponse response = httpClient.send(request);
                
                if (response.getStatusCode() == 200) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    List<Object> issues = (List<Object>) responseMap.get('issues');
                    total = (Integer) responseMap.get('total');
                    Integer maxResults = (Integer) responseMap.get('maxResults');
                    
                    System.debug('Fetched ' + (issues != null ? issues.size() : 0) + ' issues for project: ' + projectKey + 
                                ' at startAt: ' + startAt + ', total: ' + total);
                    
                    if (issues != null && !issues.isEmpty()) {
                        allIssues.addAll(issues);
                    }
                    
                    startAt += maxResults;
                } else {
                    String errorMsg = 'Jira API returned status: ' + response.getStatusCode() + 
                                    ' - ' + response.getStatus() + ' at startAt: ' + startAt;
                    System.debug(LoggingLevel.ERROR, errorMsg);
                    return 'Error: ' + errorMsg;
                }
            } catch (Exception ex) {
                String errorMsg = 'Error fetching Jira issues at startAt ' + startAt + ': ' + ex.getMessage();
                System.debug(LoggingLevel.ERROR, errorMsg);
                return 'Error: ' + errorMsg;
            }
        } while (startAt < total && Limits.getCallouts() < Limits.getLimitCallouts());
        
        Map<String, Object> finalResponse = new Map<String, Object>();
        finalResponse.put('expand', 'schema,names');
        finalResponse.put('issues', allIssues);
        finalResponse.put('total', allIssues.size());
        finalResponse.put('startAt', 0);
        finalResponse.put('maxResults', allIssues.size());
        
        String jsonResponse = JSON.serialize(finalResponse);
        System.debug('Final JSON response with ' + allIssues.size() + ' issues: ' + jsonResponse);
        return jsonResponse;
    }
    
    /**
     * @description Process Jira Tasks/Bugs/Sub-tasks and create Epic/Story and Work Item records
     * @param projectKey The Jira project key
     * @return ProcessingResult with counts, errors, and story IDs
     */
    @AuraEnabled
    public static ProcessingResult processJiraSubtasks(String projectKey) {
        ProcessingResult result = new ProcessingResult();
        
        System.debug('Entering processJiraSubtasks with projectKey: ' + projectKey);
        
        Id projectRecordId = getProjectRecordId(projectKey);
        if (projectRecordId == null) {
            result.errors.add(CONFIG.Error_Project_Not_Found__c + projectKey);
            System.debug('Error: ' + CONFIG.Error_Project_Not_Found__c + projectKey);
            return result;
        }
        
        String jiraResponse = getSubtasksForProject(projectKey);
        
        if (jiraResponse.startsWith('Error:')) {
            result.errors.add('Failed to fetch Jira issues: ' + jiraResponse);
            System.debug('Error fetching issues: ' + jiraResponse);
            return result;
        }
        
        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(jiraResponse);
            List<Object> issues = (List<Object>) responseMap.get('issues');
            
            if (issues == null || issues.isEmpty()) {
                System.debug('No issues found in Jira response');
                result.errors.add('No Tasks/Bugs/Sub-tasks found for project: ' + projectKey);
                return result;
            }
            
            System.debug('Found ' + issues.size() + ' issues in Jira response');
            
            Map<String, Map<String, Object>> parentStoriesToCreate = new Map<String, Map<String, Object>>();
            List<Map<String, Object>> closedIssuesForWorkItems = new List<Map<String, Object>>();

            for (Object issueObj : issues) {
                Map<String, Object> issue = (Map<String, Object>) issueObj;
                processIssueAndParent(issue, parentStoriesToCreate, closedIssuesForWorkItems);
            }

            System.debug('Processing ' + parentStoriesToCreate.size() + ' parent Epics/Stories (IN PROGRESS)');
            System.debug('Processing ' + closedIssuesForWorkItems.size() + ' CLOSED Tasks/Bugs/Sub-tasks for work items');

            ProcessingResult storyResult = createStoriesFromParents(new List<Map<String, Object>>(parentStoriesToCreate.values()), projectRecordId);
            result.storiesCreated = storyResult.storiesCreated;
            result.storyIds = storyResult.storyIds;
            result.workItemsCreated = createWorkItemsFromJiraIssues(closedIssuesForWorkItems, projectRecordId);

            System.debug('Final ProcessingResult: storiesCreated=' + result.storiesCreated + 
                        ', workItemsCreated=' + result.workItemsCreated + 
                        ', storyIds=' + result.storyIds + 
                        ', errors=' + result.errors);
            
        } catch (Exception ex) {
            String errorMsg = 'Error processing Jira issues: ' + ex.getMessage() + 
                            ' | Stack Trace: ' + ex.getStackTraceString();
            System.debug(LoggingLevel.ERROR, errorMsg);
            result.errors.add(errorMsg);
        }
        
        return result;
    }
    
    /**
     * @description Process Task/Bug/Sub-task and check parent Epic/Story status
     * @param issue The issue to process
     * @param parentStoriesToCreate Map to collect parent Epics/Stories that need to be created
     * @param closedIssuesForWorkItems List to collect closed Tasks/Bugs/Sub-tasks for work items
     */
    private static void processIssueAndParent(Map<String, Object> issue,
                                            Map<String, Map<String, Object>> parentStoriesToCreate,
                                            List<Map<String, Object>> closedIssuesForWorkItems) {
        Map<String, Object> fields = (Map<String, Object>) issue.get('fields');
        Map<String, Object> parent = (Map<String, Object>) fields?.get('parent');
        Map<String, Object> issueType = (Map<String, Object>) fields.get('issuetype');
        String issueTypeId = (String) issueType?.get('id');
        
        if (parent == null) {
            System.debug('Issue ' + issue.get('key') + ' has no parent');
            return;
        }
        
        String parentKey = (String) parent.get('key');
        Map<String, Object> parentFields = (Map<String, Object>) parent.get('fields');
        Map<String, Object> parentStatus = (Map<String, Object>) parentFields?.get('status');
        Map<String, Object> parentIssueType = (Map<String, Object>) parentFields?.get('issuetype');
        
        String parentStatusName = (String) parentStatus?.get('name');
        String parentIssueTypeId = (String) parentIssueType?.get('id');
        
        System.debug('Processing issue ' + issue.get('key') + 
                    ' with parent ' + parentKey + 
                    ' (Status: ' + parentStatusName + ', Type ID: ' + parentIssueTypeId + ')');
        
        Boolean isValidParent = (CONFIG.Issue_Type_Epic__c.equals(parentIssueTypeId) || 
                                CONFIG.Issue_Type_Story__c.equals(parentIssueTypeId)) && 
                                CONFIG.Parent_Status__c.equals(parentStatusName);
        
        // Updated to include Issue_Type_Bug__c in the validation
        if (isValidParent && (CONFIG.Issue_Type_Subtask__c.equals(issueTypeId) || 
                              CONFIG.Issue_Type_Task__c.equals(issueTypeId) || 
                              CONFIG.Issue_Type_Bug__c.equals(issueTypeId))) {
            if (!parentStoriesToCreate.containsKey(parentKey)) {
                parentStoriesToCreate.put(parentKey, parent);
                System.debug('Added parent Epic/Story to create: ' + parentKey);
            }
            
            Map<String, Object> issueStatus = (Map<String, Object>) fields.get('status');
            String issueStatusName = (String) issueStatus?.get('name');
            
            if (CONFIG.Sub_Task_status__c.equals(issueStatusName)) {
                List<Object> customField10157 = (List<Object>) fields?.get(CONFIG.Work_Item_Creation_Field__c);
                Boolean shouldCreateWorkItem = false;
                
                if (customField10157 != null && !customField10157.isEmpty()) {
                    Map<String, Object> fieldValue = (Map<String, Object>) customField10157[0];
                    String fieldValueStr = (String) fieldValue?.get('value');
                    shouldCreateWorkItem = 'Yes'.equals(fieldValueStr);
                }
                
                if (shouldCreateWorkItem) {
                    closedIssuesForWorkItems.add(issue);
                    System.debug('Added closed issue for work item: ' + issue.get('key'));
                } else {
                    System.debug('Skipping closed issue ' + issue.get('key') + 
                               ' - ' + CONFIG.Work_Item_Creation_Field__c + ' is not "Yes"');
                }
            } else {
                System.debug('Issue ' + issue.get('key') + ' is not closed (Status: ' + issueStatusName + ')');
            }
        } else {
            System.debug('Skipping issue ' + issue.get('key') + 
                        ' - Parent is not an IN PROGRESS Epic/Story (Parent Status: ' + parentStatusName + 
                        ', Type ID: ' + parentIssueTypeId + ')');
        }
    }
    
    /**
     * @description Create Epic/Story records from parent data
     * @param parentStories List of parent Epic/Story data
     * @param projectRecordId The Project record ID to associate with stories
     * @return ProcessingResult with stories created and their IDs
     */
    private static ProcessingResult createStoriesFromParents(List<Map<String, Object>> parentStories, Id projectRecordId) {
        ProcessingResult result = new ProcessingResult();
        
        if (parentStories == null || parentStories.isEmpty()) {
            System.debug('No parent Epics/Stories to create');
            return result;
        }
        
        Set<String> jiraKeys = new Set<String>();
        Map<String, Map<String, Object>> keyToStoryMap = new Map<String, Map<String, Object>>();
        
        for (Map<String, Object> parentStory : parentStories) {
            String key = (String) parentStory.get('key');
            if (String.isNotBlank(key)) {
                jiraKeys.add(key);
                keyToStoryMap.put(key, parentStory);
            }
        }
        
        Set<String> existingKeys = getExistingStoryKeys(jiraKeys);
        
        List<Jira_Story__c> storiesToCreate = new List<Jira_Story__c>();
        
        for (String jiraKey : jiraKeys) {
            if (existingKeys.contains(jiraKey)) {
                System.debug('Epic/Story already exists for Jira key: ' + jiraKey);
                continue;
            }
            
            Map<String, Object> parentStory = keyToStoryMap.get(jiraKey);
            Map<String, Object> fields = (Map<String, Object>) parentStory.get('fields');
            String summary = (String) fields?.get('summary');
            Map<String, Object> issueType = (Map<String, Object>) fields.get('issuetype');
            String issueTypeId = (String) issueType?.get('id');
            
            Jira_Story__c newStory = new Jira_Story__c();
            newStory.Name = String.isNotBlank(summary) ? summary.abbreviate(80) : 'Untitled Story';
            newStory.Jira_Ticket_Key__c = jiraKey;
            newStory.Status__c = CONFIG.Parent_Status__c;
            newStory.Project__c = projectRecordId;
            newStory.Type__c = CONFIG.Issue_Type_Epic__c.equals(issueTypeId) ? 'Epic' : 'Story';
            
            storiesToCreate.add(newStory);
        }
        
        if (!storiesToCreate.isEmpty()) {
            try {
                Database.SaveResult[] saveResults = Database.insert(storiesToCreate, false);
                for (Integer i = 0; i < saveResults.size(); i++) {
                    if (saveResults[i].isSuccess()) {
                        result.storiesCreated++;
                        result.storyIds.add(saveResults[i].getId());
                        System.debug('Successfully created ' + storiesToCreate[i].Type__c + ': ' + 
                                   storiesToCreate[i].Name + ' (ID: ' + saveResults[i].getId() + ')');
                    } else {
                        String errorMsg = 'Failed to create ' + storiesToCreate[i].Type__c + ': ' + 
                                        storiesToCreate[i].Name + ' - ' + 
                                        saveResults[i].getErrors()[0].getMessage();
                        logSaveErrors(saveResults[i], storiesToCreate[i].Name, storiesToCreate[i].Type__c);
                        result.errors.add(errorMsg);
                    }
                }
            } catch (DmlException ex) {
                System.debug(LoggingLevel.ERROR, 'DML Error creating Epics/Stories: ' + ex.getMessage());
                result.errors.add('DML Error creating Epics/Stories: ' + ex.getMessage());
            }
        }
        
        System.debug('createStoriesFromParents returning: storiesCreated=' + result.storiesCreated + 
                    ', storyIds=' + result.storyIds + 
                    ', errors=' + result.errors);
        return result;
    }
    
    /**
     * @description Get Project record ID by Jira project key
     * @param jiraProjectKey The Jira project key
     * @return Project record ID or null if not found
     */
    private static Id getProjectRecordId(String jiraProjectKey) {
        if (String.isBlank(jiraProjectKey)) {
            return null;
        }
        
        try {
            List<sf_devops__Project__c> projects = [
                SELECT Id, Name, Jira_Project_Key__c 
                FROM sf_devops__Project__c 
                WHERE Jira_Project_Key__c = :jiraProjectKey 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            if (!projects.isEmpty()) {
                System.debug('Found project record: ' + projects[0].Name + ' (ID: ' + projects[0].Id + ')');
                return projects[0].Id;
            }
            System.debug(LoggingLevel.WARN, 'No project found for Jira key: ' + jiraProjectKey);
            return null;
        } catch (QueryException ex) {
            System.debug(LoggingLevel.ERROR, 'Error querying project record: ' + ex.getMessage());
            return null;
        }
    }
    
    /**
     * @description Create Work Item records from Jira Task/Bug/Sub-task issues (CLOSED only)
     * @param issues List of Jira Task/Bug/Sub-task issues
     * @param projectRecordId The Project record ID to associate with work items
     * @return Number of work items created
     */
    private static Integer createWorkItemsFromJiraIssues(List<Map<String, Object>> issues, Id projectRecordId) {
        if (issues == null || issues.isEmpty()) {
            System.debug('No CLOSED Tasks/Bugs/Sub-tasks with ' + CONFIG.Work_Item_Creation_Field__c + '=Yes to create work items');
            return 0;
        }
        
        Set<String> jiraKeys = new Set<String>();
        Set<String> parentKeys = new Set<String>();
        Map<String, Map<String, Object>> keyToIssueMap = new Map<String, Map<String, Object>>();
        
        collectWorkItemKeys(issues, jiraKeys, parentKeys, keyToIssueMap);
        
        Set<String> existingWorkItemKeys = getExistingWorkItemKeys(jiraKeys);
        
        Map<String, Id> parentKeyToStoryIdMap = getStoryIdsByJiraKeys(parentKeys);
        
        List<sf_devops__Work_Item__c> workItemsToCreate = buildWorkItemsList(
            jiraKeys, existingWorkItemKeys, keyToIssueMap, parentKeyToStoryIdMap, projectRecordId
        );
        
        return insertWorkItemRecords(workItemsToCreate);
    }
    
    /**
     * @description Collect Jira keys and parent keys from Task/Bug/Sub-task issues
     * @param issues List of Task/Bug/Sub-task issues
     * @param jiraKeys Set to collect Jira keys
     * @param parentKeys Set to collect parent keys
     * @param keyToIssueMap Map to store key to issue mapping
     */
    private static void collectWorkItemKeys(List<Map<String, Object>> issues,
                                          Set<String> jiraKeys,
                                          Set<String> parentKeys,
                                          Map<String, Map<String, Object>> keyToIssueMap) {
        for (Map<String, Object> issue : issues) {
            String key = (String) issue.get('key');
            Map<String, Object> fields = (Map<String, Object>) issue.get('fields');
            Map<String, Object> parent = (Map<String, Object>) fields?.get('parent');
            
            if (String.isNotBlank(key)) {
                jiraKeys.add(key);
                keyToIssueMap.put(key, issue);
                
                if (parent != null) {
                    String parentKey = (String) parent.get('key');
                    if (String.isNotBlank(parentKey)) {
                        parentKeys.add(parentKey);
                    }
                }
            }
        }
    }
    
    /**
     * @description Build list of Work Items to create
     * @param jiraKeys Set of Jira keys
     * @param existingWorkItemKeys Set of existing work item keys
     * @param keyToIssueMap Map of key to issue
     * @param parentKeyToStoryIdMap Map of parent key to story ID
     * @param projectRecordId The Project record ID to associate with work items
     * @return List of Work Items to create
     */
    private static List<sf_devops__Work_Item__c> buildWorkItemsList(Set<String> jiraKeys,
                                                               Set<String> existingWorkItemKeys,
                                                               Map<String, Map<String, Object>> keyToIssueMap,
                                                               Map<String, Id> parentKeyToStoryIdMap,
                                                               Id projectRecordId) {
        List<sf_devops__Work_Item__c> workItemsToCreate = new List<sf_devops__Work_Item__c>();
        
        for (String jiraKey : jiraKeys) {
            if (existingWorkItemKeys.contains(jiraKey)) {
                System.debug('Work Item already exists for Jira key: ' + jiraKey);
                continue;
            }
            
            Map<String, Object> issue = keyToIssueMap.get(jiraKey);
            Map<String, Object> fields = (Map<String, Object>) issue.get('fields');
            String summary = (String) fields.get('summary');
            Map<String, Object> parent = (Map<String, Object>) fields?.get('parent');
            String parentKey = parent != null ? (String) parent.get('key') : '';
            
            sf_devops__Work_Item__c newWorkItem = new sf_devops__Work_Item__c();
            newWorkItem.sf_devops__Subject__c = 'JIRA-' + jiraKey + 
                                               (String.isNotBlank(parentKey) ? ' (' + parentKey + ')' : '') + 
                                               ': ' + (String.isNotBlank(summary) ? summary.abbreviate(80) : 'Untitled Task');
            newWorkItem.sf_devops__Development_Approved__c = false;
            newWorkItem.sf_devops__Project__c = projectRecordId;
            newWorkItem.Jira_Ticket_Key__c = jiraKey;
            
            setParentStoryReference(newWorkItem, fields, parentKeyToStoryIdMap);
            
            newWorkItem.sf_devops__Assigned_To__c = getUserIdFromCustomField(fields);
            
            Map<String, Object> worklog = (Map<String, Object>) fields.get('worklog');
            if (worklog != null) {
                List<Object> worklogs = (List<Object>) worklog.get('worklogs');
                Decimal totalTimeSpentSeconds = 0;
                if (worklogs != null) {
                    for (Object wl : worklogs) {
                        Map<String, Object> worklogEntry = (Map<String, Object>) wl;
                        Object timeSpentSecondsObj = worklogEntry.get('timeSpentSeconds');
                        if (timeSpentSecondsObj instanceof Decimal || timeSpentSecondsObj instanceof Integer) {
                            totalTimeSpentSeconds += ((Decimal) timeSpentSecondsObj);
                        }
                    }
                }
                Integer hours = (Integer) (totalTimeSpentSeconds / 3600);
                Decimal remainingSeconds = totalTimeSpentSeconds - (hours * 3600);
                Integer minutes = (Integer) (remainingSeconds / 60);
                newWorkItem.Work_logs__c = hours + 'h ' + minutes + 'm';
                System.debug('Work Item ' + jiraKey + ' total time spent: ' + totalTimeSpentSeconds + 
                             ' seconds (' + hours + 'h ' + minutes + 'm)');
            } else {
                newWorkItem.Work_logs__c = '0h 0m';
                System.debug('No worklog found for Work Item ' + jiraKey);
            }
            
            workItemsToCreate.add(newWorkItem);
        }
        
        return workItemsToCreate;
    }
    
    /**
     * @description Set parent Epic/Story reference on work item
     * @param workItem The work item to set parent reference on
     * @param fields The Jira issue fields
     * @param parentKeyToStoryIdMap Map of parent key to story ID
     */
    private static void setParentStoryReference(sf_devops__Work_Item__c workItem,
                                              Map<String, Object> fields,
                                              Map<String, Id> parentKeyToStoryIdMap) {
        Map<String, Object> parent = (Map<String, Object>) fields?.get('parent');
        if (parent != null) {
            String parentKey = (String) parent.get('key');
            if (parentKeyToStoryIdMap.containsKey(parentKey)) {
                workItem.Jira_Story__c = parentKeyToStoryIdMap.get(parentKey);
            }
        }
    }
    
    /**
     * @description Insert Work Item records with error handling
     * @param workItemsToCreate List of Work Item records to insert
     * @return Number of successfully created work items
     */
    private static Integer insertWorkItemRecords(List<sf_devops__Work_Item__c> workItemsToCreate) {
        if (workItemsToCreate.isEmpty()) {
            return 0;
        }
        
        System.debug('workItemsToCreate: ' + workItemsToCreate);
        
        try {
            Database.SaveResult[] saveResults = Database.insert(workItemsToCreate, false);
            Integer successCount = 0;
            
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    successCount++;
                    System.debug('Successfully created Work Item: ' + 
                               workItemsToCreate[i].sf_devops__Subject__c + 
                               ' (ID: ' + saveResults[i].getId() + ')');
                } else {
                    String errorMsg = 'Failed to create Work Item: ' + 
                                    workItemsToCreate[i].sf_devops__Subject__c + ' - ' + 
                                    saveResults[i].getErrors()[0].getMessage();
                    logSaveErrors(saveResults[i], workItemsToCreate[i].sf_devops__Subject__c, 'Work Item');
                    System.debug(LoggingLevel.ERROR, errorMsg);
                }
            }
            
            return successCount;
        } catch (DmlException ex) {
            System.debug(LoggingLevel.ERROR, 'DML Error creating work items: ' + ex.getMessage());
            return 0;
        }
    }
    
    /**
     * @description Log save errors for debugging
     * @param saveResult The save result with errors
     * @param recordName The name of the record
     * @param recordType The type of record (Epic/Story/Work Item)
     */
    private static void logSaveErrors(Database.SaveResult saveResult, String recordName, String recordType) {
        for (Database.Error error : saveResult.getErrors()) {
            System.debug(LoggingLevel.ERROR, 'Error creating ' + recordType + ' ' + 
                       recordName + ': ' + error.getMessage());
        }
    }
    
    /**
     * @description Build HTTP request for Jira API to get Tasks/Bugs/Sub-tasks with pagination
     * @param projectKey The Jira project key
     * @param startAt The starting index for pagination
     * @return Configured HttpRequest
     */
    private static HttpRequest buildJiraSubtaskRequest(String projectKey, Integer startAt) {
        String username = CONFIG.Jira_User_Name__c;
        String apiToken = CONFIG.Jira_API_Token__c;
        String basicAuth = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(username + ':' + apiToken));
        
        HttpRequest request = new HttpRequest();
        request.setHeader('Authorization', basicAuth);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setMethod('GET');
        request.setTimeout((Integer)CONFIG.Request_Timeout__c);
        
        String jqlQuery = buildJqlQuery(projectKey);
        String encodedJQL = EncodingUtil.urlEncode(jqlQuery, 'UTF-8');
        String fields = CONFIG.Jira_Fields__c;
        String encodedFields = EncodingUtil.urlEncode(fields, 'UTF-8');
        String endpoint = CONFIG.Jira_Base_URL__c + CONFIG.Jira_API_Endpoint__c + 
                         '?jql=' + encodedJQL + '&fields=' + encodedFields + 
                         '&startAt=' + startAt + '&maxResults=' + CONFIG.Max_Results__c;
        System.debug('endpoint: ' + endpoint);
        request.setEndpoint(endpoint);
        System.debug('Building request for projectKey: ' + projectKey + ', startAt: ' + startAt);
        
        return request;
    }
    
    /**
     * @description Build JQL query for fetching Tasks/Bugs/Sub-tasks
     * @param projectKey The Jira project key
     * @return JQL query string
     */
    private static String buildJqlQuery(String projectKey) {
        String encodedProjectKey = EncodingUtil.urlEncode(projectKey, 'UTF-8');
        // Updated to include Bug in the issuetype filter
        return 'project=' + encodedProjectKey + 
               ' AND issuetype in (Task, Bug, subTaskIssueTypes())' + 
               ' AND Sprint in openSprints()' + 
               ' AND statusCategory=Done' + 
               ' AND "Push To DevOps" in ("Yes")';
    }
    
    /**
     * @description Get existing Epic/Story keys from database
     * @param jiraKeys Set of Jira keys to check
     * @return Set of existing Jira keys
     */
    private static Set<String> getExistingStoryKeys(Set<String> jiraKeys) {
        Set<String> existingKeys = new Set<String>();
        
        if (jiraKeys.isEmpty()) {
            return existingKeys;
        }
        
        try {
            List<Jira_Story__c> existingStories = [
                SELECT Id, Jira_Ticket_Key__c 
                FROM Jira_Story__c 
                WHERE Jira_Ticket_Key__c IN :jiraKeys
                WITH SECURITY_ENFORCED
            ];
            
            for (Jira_Story__c story : existingStories) {
                existingKeys.add(story.Jira_Ticket_Key__c);
            }
        } catch (QueryException ex) {
            System.debug(LoggingLevel.ERROR, 'Error querying existing Epics/Stories: ' + ex.getMessage());
        }
        
        return existingKeys;
    }
    
    /**
     * @description Get existing Work Item keys from database
     * @param jiraKeys Set of Jira keys to check
     * @return Set of existing Jira keys
     */
    private static Set<String> getExistingWorkItemKeys(Set<String> jiraKeys) {
        Set<String> existingKeys = new Set<String>();
        
        if (jiraKeys.isEmpty()) {
            return existingKeys;
        }
        
        try {
            List<sf_devops__Work_Item__c> existingWorkItems = [
                SELECT Id, Jira_Ticket_Key__c 
                FROM sf_devops__Work_Item__c 
                WHERE Jira_Ticket_Key__c IN :jiraKeys
                WITH SECURITY_ENFORCED
            ];
            
            for (sf_devops__Work_Item__c workItem : existingWorkItems) {
                existingKeys.add(workItem.Jira_Ticket_Key__c);
            }
        } catch (QueryException ex) {
            System.debug(LoggingLevel.ERROR, 'Error querying existing work items: ' + ex.getMessage());
        }
        
        return existingKeys;
    }
    
    /**
     * @description Get Epic/Story IDs by Jira keys for parent relationship mapping
     * @param jiraKeys Set of Jira keys
     * @return Map of Jira key to Epic/Story ID
     */
    private static Map<String, Id> getStoryIdsByJiraKeys(Set<String> jiraKeys) {
        Map<String, Id> keyToIdMap = new Map<String, Id>();
        
        if (jiraKeys.isEmpty()) {
            return keyToIdMap;
        }
        
        try {
            List<Jira_Story__c> stories = [
                SELECT Id, Jira_Ticket_Key__c 
                FROM Jira_Story__c 
                WHERE Jira_Ticket_Key__c IN :jiraKeys
                WITH SECURITY_ENFORCED
            ];
            
            for (Jira_Story__c story : stories) {
                keyToIdMap.put(story.Jira_Ticket_Key__c, story.Id);
            }
        } catch (QueryException ex) {
            System.debug(LoggingLevel.ERROR, 'Error querying Epics/Stories by keys: ' + ex.getMessage());
        }
        
        return keyToIdMap;
    }
    
    /**
     * @description Extract user ID from Jira custom field or return default
     * @param fields Map of Jira issue fields
     * @return User ID
     */
    private static Id getUserIdFromCustomField(Map<String, Object> fields) {
        try {
            Object assigneeField = fields?.get(CONFIG.Assignee_Field__c);
            String userEmail;
            
            if (assigneeField instanceof Map<String, Object>) {
                userEmail = (String) ((Map<String, Object>) assigneeField).get('value');
            }
            
            if (String.isNotBlank(userEmail)) {
                List<User> users = [
                    SELECT Id 
                    FROM User 
                    WHERE Email = :userEmail 
                    AND IsActive = true 
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    return users[0].Id;
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Error extracting user from custom field: ' + ex.getMessage());
        }
        
        return CONFIG.Default_User_ID__c;
    }
}