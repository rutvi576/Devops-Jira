/**
 * @description Handler class for JiraStoryTrigger
 * @author Simran Nandla
 * @date 2025-06-16
 */
public class JiraStoryTriggerHandler {
    
    // Retrieve custom metadata configuration
    private static final Jira_Configuration__mdt CONFIG = [
        SELECT SF_Ready_For_QA_Status__c, SF_In_UAT_Status__c, SF_Status_Closed__c
        FROM Jira_Configuration__mdt
        WHERE DeveloperName = 'Default_Jira_Configuration'
        LIMIT 1
    ];
    
    /**
     * @description Handle after update events for Jira Story records
     * @param newRecords List of updated Jira Story records
     * @param oldMap Map of old Jira Story records
     */
    public static void handleAfterUpdate(List<Jira_Story__c> newRecords, Map<Id, Jira_Story__c> oldMap) {
        Set<String> jiraTicketKeysForQA = new Set<String>();
        Set<String> jiraTicketKeysForDeployed = new Set<String>();
        Set<String> jiraTicketKeysForClosed = new Set<String>();
        
        for (Jira_Story__c newStory : newRecords) {
            Jira_Story__c oldStory = oldMap.get(newStory.Id);
            
            // Check if status changed and has valid ticket key
            if (newStory.Status__c != oldStory.Status__c && String.isNotBlank(newStory.Jira_Ticket_Key__c)) {
                if (newStory.Status__c == CONFIG.SF_Ready_For_QA_Status__c) {
                    jiraTicketKeysForQA.add(newStory.Jira_Ticket_Key__c);
                } else if (newStory.Status__c == CONFIG.SF_In_UAT_Status__c) {
                    jiraTicketKeysForDeployed.add(newStory.Jira_Ticket_Key__c);
                } else if (newStory.Status__c == CONFIG.SF_Status_Closed__c) {
                    jiraTicketKeysForClosed.add(newStory.Jira_Ticket_Key__c);
                }
            }
        }
        
        // Make async API calls to Jira if there are tickets to update
        if (!jiraTicketKeysForQA.isEmpty()) {
            JiraIntegrationService.updateJiraIssueStatusAsync(jiraTicketKeysForQA, CONFIG.SF_Ready_For_QA_Status__c);
        }
        if (!jiraTicketKeysForDeployed.isEmpty()) {
            JiraIntegrationService.updateJiraIssueStatusAsync(jiraTicketKeysForDeployed, CONFIG.SF_In_UAT_Status__c);
        }
        if (!jiraTicketKeysForClosed.isEmpty()) {
            JiraIntegrationService.updateJiraIssueStatusAsync(jiraTicketKeysForClosed, CONFIG.SF_Status_Closed__c);
        }
    }
}