/**
 * @description Handler class for WorkItemTrigger
 * @author Simran Nandla
 * @date 2025-06-16
 */
public with sharing class WorkItemTriggerHandler {
    
    /*private static final String Work_Item_Promoted_Status__c = 'Promoted';
    private static final String SF_Ready_For_QA_Status__c = 'IN QA';
    private static final String SF_In_UAT_Status__c = 'IN UAT'; 
    private static final String Work_Item_In_Progress_Status__c = 'IN_PROGRESS';
    private static final String Work_Item_Closed_Status__c = 'CLOSED'; // New constant for Closed status*/
    
    // Retrieve custom metadata configuration
    private static final Jira_Configuration__mdt CONFIG1 = [
        SELECT Work_Item_Promoted_Status__c,Work_Item_In_Progress_Status__c,Work_Item_Closed_Status__c,
                SF_In_UAT_Status__c,SF_Ready_For_QA_Status__c
        FROM Jira_Configuration__mdt
        WHERE DeveloperName = 'Default_Jira_Configuration'
        LIMIT 1
    ];

    /**
     * @description Handle before update events for validation
     * @param newRecords List of updated work item records
     * @param oldMap Map of old work item records
     */
    public static void handleBeforeUpdate(List<sf_devops__Work_Item__c> newRecords, Map<Id, sf_devops__Work_Item__c> oldMap) {
        //validatePromotion(newRecords, oldMap);
    }
    
    /**
     * @description Handle after insert and undelete events
     * @param newRecords List of new work item records
     */
    public static void handleAfterInsertUndelete(List<sf_devops__Work_Item__c> newRecords) {
        processJiraStoryUpdates(newRecords, null);
    }
    
    /**
     * @description Handle after update events
     * @param newRecords List of updated work item records
     * @param oldMap Map of old work item records
     */
    public static void handleAfterUpdate(List<sf_devops__Work_Item__c> newRecords, Map<Id, sf_devops__Work_Item__c> oldMap) {
        processJiraStoryUpdates(newRecords, oldMap);
        handleAfterUpdateAddComment(newRecords, oldMap);
    }
    
    /**
     * @description Handle after delete events
     * @param oldRecords List of deleted work item records
     */
    public static void handleAfterDelete(List<sf_devops__Work_Item__c> oldRecords) {
        processJiraStoryUpdates(oldRecords, null);
    }
    
    /**
     * @description Extract Jira Story IDs from work item records
     * @param workItems List of work item records
     * @return Set of Jira Story IDs
     */
    @TestVisible
    private static Set<Id> getJiraStoryIds(List<sf_devops__Work_Item__c> workItems) {
        Set<Id> jiraStoryIds = new Set<Id>();
        for (sf_devops__Work_Item__c workItem : workItems) {
            if (workItem.Jira_Story__c != null) {
                jiraStoryIds.add(workItem.Jira_Story__c);
            }
        }
        return jiraStoryIds;
    }

    /**
 * @description Validate that all sibling work items are development approved before promotion
 * @param newRecords List of updated work item records
 * @param oldMap Map of old work item records
 */
/*@TestVisible
private static void validatePromotion(List<sf_devops__Work_Item__c> newRecords, Map<Id, sf_devops__Work_Item__c> oldMap) {
    System.debug(LoggingLevel.INFO, '=== validatePromotion START ===');
    
    // Collect Jira Story IDs for work items transitioning from APPROVED to PROMOTED
    Set<Id> jiraStoryIds = new Set<Id>();
    
    for (sf_devops__Work_Item__c workItem : newRecords) {
        sf_devops__Work_Item__c oldWorkItem = oldMap.get(workItem.Id);
        
        // Check if work item is transitioning from APPROVED to PROMOTED
        if (workItem.sf_devops__State__c == 'PROMOTED' && 
            oldWorkItem.sf_devops__State__c == 'APPROVED' && 
            workItem.Jira_Story__c != null) {
            
            jiraStoryIds.add(workItem.Jira_Story__c);
            System.debug(LoggingLevel.INFO, 'Work Item transitioning to PROMOTED: ' + workItem.Name + ' for Story: ' + workItem.Jira_Story__c);
        }
    }
    
    if (jiraStoryIds.isEmpty()) {
        System.debug(LoggingLevel.INFO, 'No work items transitioning from APPROVED to PROMOTED - exiting validation');
        return;
    }
    
    // Query all work items for the relevant Jira Stories
    List<sf_devops__Work_Item__c> allWorkItems = [
        SELECT Id, Jira_Story__c, Name, sf_devops__Development_Approved__c
        FROM sf_devops__Work_Item__c
        WHERE Jira_Story__c IN :jiraStoryIds
    ];
    
    // Group work items by Jira Story
    Map<Id, List<sf_devops__Work_Item__c>> storyToWorkItemsMap = new Map<Id, List<sf_devops__Work_Item__c>>();
    for (sf_devops__Work_Item__c workItem : allWorkItems) {
        if (!storyToWorkItemsMap.containsKey(workItem.Jira_Story__c)) {
            storyToWorkItemsMap.put(workItem.Jira_Story__c, new List<sf_devops__Work_Item__c>());
        }
        storyToWorkItemsMap.get(workItem.Jira_Story__c).add(workItem);
    }
    
    // Track validation errors for potential exception throwing
    List<String> validationErrors = new List<String>();
    
    // Validate each work item transitioning to PROMOTED
    for (sf_devops__Work_Item__c workItem : newRecords) {
        sf_devops__Work_Item__c oldWorkItem = oldMap.get(workItem.Id);
        
        // Only validate work items transitioning from APPROVED to PROMOTED
        if (workItem.sf_devops__State__c == 'PROMOTED' && 
            oldWorkItem.sf_devops__State__c == 'APPROVED' && 
            workItem.Jira_Story__c != null) {
            
            System.debug(LoggingLevel.INFO, 'Validating work item: ' + workItem.Name);
            
            // Get all work items for this Jira Story
            List<sf_devops__Work_Item__c> siblingWorkItems = storyToWorkItemsMap.get(workItem.Jira_Story__c);
            
            if (siblingWorkItems != null && !siblingWorkItems.isEmpty()) {
                // Check if ANY work item in the story is NOT development approved
                List<String> notDevelopmentApprovedItems = new List<String>();
                
                for (sf_devops__Work_Item__c sibling : siblingWorkItems) {
                    if (sibling.sf_devops__Development_Approved__c != true) {
                        notDevelopmentApprovedItems.add(sibling.Name);
                        System.debug(LoggingLevel.INFO, 'Work item NOT development approved: ' + sibling.Name);
                    }
                }
                
                // If ANY work item is not development approved, block the promotion
                if (!notDevelopmentApprovedItems.isEmpty()) {
                    String errorMessage = 'Cannot promote work item "' + workItem.Name + '": All work items in the Jira Story must have Development Approved = true before any work item can be promoted. ' +
                                         'Work items not development approved: ' + String.join(notDevelopmentApprovedItems, ', ');
                    
                    // OPTION 1: Standard addError (your current approach)
                    workItem.addError(errorMessage);
                    
                    // OPTION 2: Add error to specific field (more visible in some UIs)
                    workItem.sf_devops__State__c.addError(errorMessage);
                    
                    // OPTION 3: Collect errors for potential exception throwing
                    validationErrors.add(errorMessage);
                    
                    System.debug(LoggingLevel.ERROR, 'Blocking promotion for: ' + workItem.Name + ' - Error: ' + errorMessage);
                } else {
                    System.debug(LoggingLevel.INFO, 'All work items are development approved - allowing promotion for: ' + workItem.Name);
                }
            }
        }
    }
    
    // OPTION 4: Throw a custom exception if any validation errors occurred
    // This will halt the entire transaction and show error prominently
    if (!validationErrors.isEmpty()) {
        String combinedErrorMessage = 'Work Item Promotion Blocked:\n\n' + String.join(validationErrors, '\n\n');
        throw new WorkItemPromotionException(combinedErrorMessage);
    }
    
    System.debug(LoggingLevel.INFO, '=== validatePromotion END ===');
}*/

/**
 * @description Custom exception class for Work Item promotion validation
 */
public class WorkItemPromotionException extends Exception {}
    
    /**
     * @description Process Jira Story status and completion percentage updates
     * @param workItems List of work item records
     * @param oldMap Map of old work item records (null for insert/delete)
     */
    private static void processJiraStoryUpdates(List<sf_devops__Work_Item__c> workItems, Map<Id, sf_devops__Work_Item__c> oldMap) {
        Set<Id> jiraStoryIds = new Set<Id>();
        
        // Collect Jira Story IDs based on status or Ready_for_UAT__c changes
        if (oldMap != null) { // Update context
            for (sf_devops__Work_Item__c workItem : workItems) {
                sf_devops__Work_Item__c oldWorkItem = oldMap.get(workItem.Id);
                if (workItem.Jira_Story__c != null && 
                    (workItem.sf_devops__State__c != oldWorkItem.sf_devops__State__c || 
                     workItem.Ready_for_UAT__c != oldWorkItem.Ready_for_UAT__c)) {
                    jiraStoryIds.add(workItem.Jira_Story__c);
                }
            }
        } else { // Insert or Delete context
            jiraStoryIds = getJiraStoryIds(workItems);
        }
        
        if (!jiraStoryIds.isEmpty()) {
            updateJiraStoryStatus(jiraStoryIds);
            updateStoryCompletionPercentage(jiraStoryIds);
        }
    }
    
    /**
     * @description Update Jira Story status based on child work item statuses and Ready_for_UAT__c
     * @param jiraStoryIds Set of Jira Story IDs to process
     */
    @TestVisible
    private static void updateJiraStoryStatus(Set<Id> jiraStoryIds) {
        try {
            // Query all work items for the given Jira Stories
            Map<Id, List<sf_devops__Work_Item__c>> storyToWorkItemsMap = new Map<Id, List<sf_devops__Work_Item__c>>();
            for (sf_devops__Work_Item__c workItem : [
                SELECT Id, Jira_Story__c, sf_devops__State__c, Ready_for_UAT__c
                FROM sf_devops__Work_Item__c
                WHERE Jira_Story__c IN :jiraStoryIds
            ]) {
                if (!storyToWorkItemsMap.containsKey(workItem.Jira_Story__c)) {
                    storyToWorkItemsMap.put(workItem.Jira_Story__c, new List<sf_devops__Work_Item__c>());
                }
                storyToWorkItemsMap.get(workItem.Jira_Story__c).add(workItem);
            }
            
            // Query Jira Stories to update
            Map<Id, Jira_Story__c> jiraStoriesToUpdate = new Map<Id, Jira_Story__c>([
                SELECT Id, Status__c
                FROM Jira_Story__c
                WHERE Id IN :jiraStoryIds
            ]);
            
            List<Jira_Story__c> storiesToUpdate = new List<Jira_Story__c>();
            
            for (Id storyId : jiraStoryIds) {
                List<sf_devops__Work_Item__c> childWorkItems = storyToWorkItemsMap.get(storyId);
                if (childWorkItems == null || childWorkItems.isEmpty()) {
                    continue;
                }
                
                // Check if all child work items are Ready for UAT
                Boolean allReadyForUAT = true;
                Boolean allPromoted = true;
                Boolean allClosed = true; // New flag for Closed status
                for (sf_devops__Work_Item__c workItem : childWorkItems) {
                    if (!workItem.Ready_for_UAT__c) {
                        allReadyForUAT = false;
                    }
                    if (workItem.sf_devops__State__c != CONFIG1.Work_Item_Promoted_Status__c) {
                        allPromoted = false;
                    }
                    if (workItem.sf_devops__State__c != CONFIG1.Work_Item_Closed_Status__c) {
                        allClosed = false;
                    }
                }
                
                Jira_Story__c jiraStory = jiraStoriesToUpdate.get(storyId);
                if (jiraStory == null) {
                    continue;
                }
                
                // Update status to Closed if all work items are Closed
                if (allClosed && jiraStory.Status__c != CONFIG1.Work_Item_Closed_Status__c) {
                    jiraStory.Status__c = CONFIG1.Work_Item_Closed_Status__c;
                    storiesToUpdate.add(jiraStory);
                    System.debug(LoggingLevel.INFO, 'Updating Jira Story ' + jiraStory.Id + ' to Closed as all work items are Closed');
                }
                // Update status to IN UAT if all work items are Ready_for_UAT__c and not already Closed
                else if (allReadyForUAT && jiraStory.Status__c != CONFIG1.SF_In_UAT_Status__c && jiraStory.Status__c != CONFIG1.Work_Item_Closed_Status__c) {
                    jiraStory.Status__c = CONFIG1.SF_In_UAT_Status__c;
                    storiesToUpdate.add(jiraStory);
                    System.debug(LoggingLevel.INFO, 'Updating Jira Story ' + jiraStory.Id + ' to IN UAT as all work items are Ready for UAT');
                }
                // Update status to IN QA if all work items are Promoted and not already in IN QA, IN UAT, or Closed
                else if (allPromoted && jiraStory.Status__c != CONFIG1.SF_Ready_For_QA_Status__c && 
                         jiraStory.Status__c != CONFIG1.SF_In_UAT_Status__c && jiraStory.Status__c != CONFIG1.Work_Item_Closed_Status__c) {
                    jiraStory.Status__c = CONFIG1.SF_Ready_For_QA_Status__c;
                    storiesToUpdate.add(jiraStory);
                    System.debug(LoggingLevel.INFO, 'Updating Jira Story ' + jiraStory.Id + ' to IN QA as all work items are Promoted');
                }
            }
            
            if (!storiesToUpdate.isEmpty()) {
                Database.update(storiesToUpdate, false); // Partial success allowed
                System.debug(LoggingLevel.INFO, 'Updated ' + storiesToUpdate.size() + ' Jira Stories');
            }
            
        } catch (Exception ex) {
            // Log error to custom object or error personally logging framework
            System.debug(LoggingLevel.ERROR, 'Error in WorkItemTriggerHandler.updateJiraStoryStatus: ' + ex.getMessage());
            //throw new WorkItemTriggerException 'Failed to update Jira Story status: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Handle after update events to add comments to Jira
     * @param newRecords List of updated work item records
     * @param oldMap Map of old work item records
     */
    public static void handleAfterUpdateAddComment(List<sf_devops__Work_Item__c> newRecords, Map<Id, sf_devops__Work_Item__c> oldMap) {
        List<sf_devops__Work_Item__c> workItemsForComment = new List<sf_devops__Work_Item__c>();
        
        for (sf_devops__Work_Item__c workItem : newRecords) {
            sf_devops__Work_Item__c oldWorkItem = oldMap.get(workItem.Id);
            
            // If status changed to In Progress and branch is populated, prepare for Jira comment
            if (workItem.sf_devops__State__c == CONFIG1.Work_Item_In_Progress_Status__c &&
                workItem.sf_devops__State__c != oldWorkItem.sf_devops__State__c &&
                String.isNotBlank(workItem.sf_devops__Branch__c) &&
                String.isNotBlank(workItem.Jira_Ticket_Key__c)) {
                workItemsForComment.add(workItem);
            }
        }
        
        if (!workItemsForComment.isEmpty()) {
            makeJiraCommentCallouts(workItemsForComment);
        }
    }
    
    /**
     * @description Initiates future callout for Jira comment creation
     * @param workItems List of Work Items meeting callout condition
     */
    @TestVisible
    private static void makeJiraCommentCallouts(List<sf_devops__Work_Item__c> workItems) {
        Set<Id> branchIds = new Set<Id>();
        for (sf_devops__Work_Item__c item : workItems) {
            branchIds.add(item.sf_devops__Branch__c);
        }
        
        Map<Id, sf_devops__Branch__c> branches = new Map<Id, sf_devops__Branch__c>([
            SELECT Id, sf_devops__Repository__c
            FROM sf_devops__Branch__c
            WHERE Id IN :branchIds
        ]);
        
        Set<Id> repoIds = new Set<Id>();
        for (sf_devops__Branch__c branch : branches.values()) {
            if (branch.sf_devops__Repository__c != null) {
                repoIds.add(branch.sf_devops__Repository__c);
            }
        }
        
        Map<Id, sf_devops__Repository__c> repos = new Map<Id, sf_devops__Repository__c>([
            SELECT Id, sf_devops__Url__c
            FROM sf_devops__Repository__c
            WHERE Id IN :repoIds
        ]);
        
        for (sf_devops__Work_Item__c item : workItems) {
            sf_devops__Branch__c branch = branches.get(item.sf_devops__Branch__c);
            if (branch == null || branch.sf_devops__Repository__c == null) {
                continue;
            }
            
            sf_devops__Repository__c repo = repos.get(branch.sf_devops__Repository__c);
            if (repo == null || String.isBlank(repo.sf_devops__Url__c)) {
                continue;
            }
            
            String commentUrl = repo.sf_devops__Url__c + '/tree/' + item.Name;
            callJiraAddComment(item.Jira_Ticket_Key__c, commentUrl);
        }
    }
    
    /**
     * @description Future method to make Jira API callout to add a comment
     * @param issueKey Jira issue key from Work Item
     * @param commentUrl Branch URL to post as comment
     */
    @future(callout=true)
    private static void callJiraAddComment(String issueKey, String commentUrl) {
        try {
            final String JIRA_BASE_URL = 'https://getoncrm.atlassian.net';
            final String COMMENT_ENDPOINT = '/rest/api/3/issue/' + EncodingUtil.urlEncode(issueKey, 'UTF-8') + '/comment';
            final Integer REQUEST_TIMEOUT = 60000;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(JIRA_BASE_URL + COMMENT_ENDPOINT);
            request.setMethod('POST');
            request.setTimeout(REQUEST_TIMEOUT);
            request.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(System.Label.Jira_User_Name + ':' + System.Label.Jira_API_Token)));
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Accept', 'application/json');
            
            Map<String, Object> commentBody = new Map<String, Object>{
                'type' => 'doc',
                'version' => 1,
                'content' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'paragraph',
                        'content' => new List<Object>{
                            new Map<String, Object>{
                                'type' => 'text',
                                'text' => 'Branch Deployed: ' + commentUrl
                            }
                        }
                    }
                }
            };
            
            request.setBody(JSON.serialize(new Map<String, Object>{ 'body' => commentBody }));
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() != 201) {
                System.debug(LoggingLevel.ERROR, 'Jira comment post failed. Status: ' + response.getStatus() + ', Body: ' + response.getBody());
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error in callJiraAddComment: ' + ex.getMessage());
        }
    }
    
    /**
 * @description Update completion percentage for Jira Stories
 * @param storyIds Set of Jira Story IDs
 */
public static void updateStoryCompletionPercentage(Set<Id> storyIds) {
    if (storyIds.isEmpty()) {
        return;
    }
    
    // Query work items and group by Jira Story
    Map<Id, List<sf_devops__Work_Item__c>> storyToWorkItems = new Map<Id, List<sf_devops__Work_Item__c>>();
    for (sf_devops__Work_Item__c wi : [
        SELECT Id, Jira_Story__c, sf_devops__State__c
        FROM sf_devops__Work_Item__c
        WHERE Jira_Story__c IN :storyIds
    ]) {
        if (!storyToWorkItems.containsKey(wi.Jira_Story__c)) {
            storyToWorkItems.put(wi.Jira_Story__c, new List<sf_devops__Work_Item__c>());
        }
        storyToWorkItems.get(wi.Jira_Story__c).add(wi);
    }
    
    // Query existing completion percentages for Jira Stories
    Map<Id, Jira_Story__c> jiraStories = new Map<Id, Jira_Story__c>([
        SELECT Id, Completion_Percentage__c
        FROM Jira_Story__c
        WHERE Id IN :storyIds
    ]);
    
    List<Jira_Story__c> storiesToUpdate = new List<Jira_Story__c>();
    for (Id storyId : storyToWorkItems.keySet()) {
        List<sf_devops__Work_Item__c> items = storyToWorkItems.get(storyId);
        Integer total = items.size();
        Integer promotedCount = 0;
        Boolean allClosed = true;
        
        // Count promoted work items and check if all are closed
        for (sf_devops__Work_Item__c wi : items) {
            if (wi.sf_devops__State__c == CONFIG1.Work_Item_Promoted_Status__c) {
                promotedCount++;
            }
            if (wi.sf_devops__State__c != CONFIG1.Work_Item_Closed_Status__c) {
                allClosed = false;
            }
        }
        
        Jira_Story__c jiraStory = jiraStories.get(storyId);
        if (jiraStory == null) {
            continue;
        }
        
        // If all work items are closed, preserve the existing completion percentage
        if (allClosed && jiraStory.Completion_Percentage__c != null) {
            System.debug(LoggingLevel.INFO, 'All work items for Jira Story ' + storyId + ' are closed. Preserving Completion_Percentage__c: ' + jiraStory.Completion_Percentage__c);
            continue; // Skip updating the percentage
        }
        
        // Calculate and update completion percentage
        Decimal percentComplete = total > 0 ? ((Decimal)promotedCount / total * 100).setScale(2) : 0;
        storiesToUpdate.add(new Jira_Story__c(
            Id = storyId,
            Completion_Percentage__c = percentComplete
        ));
        System.debug(LoggingLevel.INFO, 'Updating Jira Story ' + storyId + ' Completion_Percentage__c to: ' + percentComplete);
    }
    
    if (!storiesToUpdate.isEmpty()) {
        Database.update(storiesToUpdate, false);
        System.debug(LoggingLevel.INFO, 'Updated ' + storiesToUpdate.size() + ' Jira Stories with new completion percentages');
    }
}
    
    /**
     * @description Custom exception class for WorkItem trigger operations
     */
    public class WorkItemTriggerException extends Exception {}

    /**
 * @description Validate that all sibling work items are development approved before promotion
 * @param newRecords List of updated work item records
 * @param oldMap Map of old work item records
 */
/*@TestVisible
private static void validatePromotion(List<sf_devops__Work_Item__c> newRecords, Map<Id, sf_devops__Work_Item__c> oldMap) {
    System.debug(LoggingLevel.INFO, '=== validatePromotion START ===');
    
    // Collect Jira Story IDs for work items transitioning from APPROVED to PROMOTED
    Set<Id> jiraStoryIds = new Set<Id>();
    
    for (sf_devops__Work_Item__c workItem : newRecords) {
        sf_devops__Work_Item__c oldWorkItem = oldMap.get(workItem.Id);
        
        // Check if work item is transitioning from APPROVED to PROMOTED
        if (workItem.sf_devops__State__c == 'PROMOTED' && 
            oldWorkItem.sf_devops__State__c == 'APPROVED' && 
            workItem.Jira_Story__c != null) {
            
            jiraStoryIds.add(workItem.Jira_Story__c);
            System.debug(LoggingLevel.INFO, 'Work Item transitioning to PROMOTED: ' + workItem.Name + ' for Story: ' + workItem.Jira_Story__c);
        }
    }
    
    if (jiraStoryIds.isEmpty()) {
        System.debug(LoggingLevel.INFO, 'No work items transitioning from APPROVED to PROMOTED - exiting validation');
        return;
    }
    
    // Query all work items for the relevant Jira Stories
    List<sf_devops__Work_Item__c> allWorkItems = [
        SELECT Id, Jira_Story__c, Name, sf_devops__Development_Approved__c
        FROM sf_devops__Work_Item__c
        WHERE Jira_Story__c IN :jiraStoryIds
    ];
    
    // Group work items by Jira Story
    Map<Id, List<sf_devops__Work_Item__c>> storyToWorkItemsMap = new Map<Id, List<sf_devops__Work_Item__c>>();
    for (sf_devops__Work_Item__c workItem : allWorkItems) {
        if (!storyToWorkItemsMap.containsKey(workItem.Jira_Story__c)) {
            storyToWorkItemsMap.put(workItem.Jira_Story__c, new List<sf_devops__Work_Item__c>());
        }
        storyToWorkItemsMap.get(workItem.Jira_Story__c).add(workItem);
    }
    
    // Track validation errors for potential exception throwing
    List<String> validationErrors = new List<String>();
    
    // Validate each work item transitioning to PROMOTED
    for (sf_devops__Work_Item__c workItem : newRecords) {
        sf_devops__Work_Item__c oldWorkItem = oldMap.get(workItem.Id);
        
        // Only validate work items transitioning from APPROVED to PROMOTED
        if (workItem.sf_devops__State__c == 'PROMOTED' && 
            oldWorkItem.sf_devops__State__c == 'APPROVED' && 
            workItem.Jira_Story__c != null) {
            
            System.debug(LoggingLevel.INFO, 'Validating work item: ' + workItem.Name);
            
            // Get all work items for this Jira Story
            List<sf_devops__Work_Item__c> siblingWorkItems = storyToWorkItemsMap.get(workItem.Jira_Story__c);
            
            if (siblingWorkItems != null && !siblingWorkItems.isEmpty()) {
                // Check if ANY work item in the story is NOT development approved
                List<String> notDevelopmentApprovedItems = new List<String>();
                
                for (sf_devops__Work_Item__c sibling : siblingWorkItems) {
                    if (sibling.sf_devops__Development_Approved__c != true) {
                        notDevelopmentApprovedItems.add(sibling.Name);
                        System.debug(LoggingLevel.INFO, 'Work item NOT development approved: ' + sibling.Name);
                    }
                }
                
                // If ANY work item is not development approved, block the promotion
                if (!notDevelopmentApprovedItems.isEmpty()) {
                    String errorMessage = 'Cannot promote work item "' + workItem.Name + '": All work items in the Jira Story must have Development Approved = true before any work item can be promoted. ' +
                                         'Work items not development approved: ' + String.join(notDevelopmentApprovedItems, ', ');
                    
                    // OPTION 1: Standard addError (your current approach)
                    workItem.addError(errorMessage);
                    
                    // OPTION 2: Add error to specific field (more visible in some UIs)
                    workItem.sf_devops__State__c.addError(errorMessage);
                    
                    // OPTION 3: Collect errors for potential exception throwing
                    validationErrors.add(errorMessage);
                    
                    System.debug(LoggingLevel.ERROR, 'Blocking promotion for: ' + workItem.Name + ' - Error: ' + errorMessage);
                } else {
                    System.debug(LoggingLevel.INFO, 'All work items are development approved - allowing promotion for: ' + workItem.Name);
                }
            }
        }
    }
    
    // OPTION 4: Throw a custom exception if any validation errors occurred
    // This will halt the entire transaction and show error prominently
    if (!validationErrors.isEmpty()) {
        String combinedErrorMessage = 'Work Item Promotion Blocked:\n\n' + String.join(validationErrors, '\n\n');
        throw new WorkItemPromotionException(combinedErrorMessage);
    }
    
    System.debug(LoggingLevel.INFO, '=== validatePromotion END ===');
}*/
}