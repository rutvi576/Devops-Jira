/**
 * @description Controller class for Jira Story Work Item Creator LWC
 * @author Your Name
 * @date 2025-06-16
 */
public with sharing class JiraStoryController {
    
    /**
     * @description Get Stories with their related Work Items for display in LWC
     * @param storyIds List of Story IDs to filter by
     * @return List of Jira_Story__c records with related Work Items
     */
    @AuraEnabled(cacheable=false)
    public static List<Jira_Story__c> getStoriesWithWorkItems(List<String> storyIds) {
        try {
            System.debug('getStoriesWithWorkItems called with storyIds: ' + storyIds);
            
            if (storyIds == null || storyIds.isEmpty()) {
                System.debug('No storyIds provided, returning empty list');
                return new List<Jira_Story__c>();
            }
            
            // Validate storyIds
            Set<String> sanitizedStoryIds = new Set<String>();
            for (String storyId : storyIds) {
                if (String.isNotBlank(storyId) && Pattern.matches('[a-zA-Z0-9]{15}|[a-zA-Z0-9]{18}', storyId)) {
                    sanitizedStoryIds.add(storyId);
                }
            }
            
            if (sanitizedStoryIds.isEmpty()) {
                System.debug('No valid story IDs after sanitization, returning empty list');
                return new List<Jira_Story__c>();
            }
            
            System.debug('Querying stories with sanitizedStoryIds: ' + sanitizedStoryIds);
            
            List<Jira_Story__c> stories = [
                SELECT Id, Name, Jira_Ticket_Key__c, CreatedDate, Completion_Percentage__c,
                       (SELECT Id, sf_devops__Subject__c, sf_devops__Assigned_To__c,
                               sf_devops__Assigned_To__r.Name, Jira_Ticket_Key__c,
                               sf_devops__State__c, CreatedDate
                        FROM Work_Items__r
                        ORDER BY CreatedDate DESC)
                FROM Jira_Story__c
                WHERE Id IN :sanitizedStoryIds
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            
            System.debug('Found ' + stories.size() + ' stories');
            for (Jira_Story__c story : stories) {
                System.debug('Story: ' + story.Id + ', Name: ' + story.Name + 
                            ', Work Items: ' + (story.Work_Items__r != null ? story.Work_Items__r.size() : 0));
            }
            
            return stories;
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error fetching stories: ' + ex.getMessage() + 
                        ' | Stack Trace: ' + ex.getStackTraceString());
            throw new AuraHandledException('Error fetching stories: ' + ex.getMessage());
        }
    }
    
    /**
     * @description Get Jira Project Key from Project record
     * @param recordId The Project record ID
     * @return Jira Project Key
     */
    @AuraEnabled(cacheable=false)
    public static String getProjectJiraKey(Id recordId) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('Record ID is required');
            }
            
            List<sf_devops__Project__c> projects = [
                SELECT Id, Jira_Project_Key__c 
                FROM sf_devops__Project__c 
                WHERE Id = :recordId 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            if (projects.isEmpty()) {
                throw new AuraHandledException('Project record not found');
            }
            
            sf_devops__Project__c project = projects[0];
            
            if (String.isBlank(project.Jira_Project_Key__c)) {
                throw new AuraHandledException('Jira Project Key is not configured');
            }
            
            System.debug('Returning Jira Project Key: ' + project.Jira_Project_Key__c);
            return project.Jira_Project_Key__c;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting project Jira key: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving Jira Project Key: ' + e.getMessage());
        }
    }
}