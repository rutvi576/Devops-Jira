/**
 * @description Trigger for Jira_Story__c object
 * @author Simran Nandla
 * @date 2025-06-16
 */
trigger JiraStoryTrigger on Jira_Story__c (after update) {
    
    if (Trigger.isAfter && Trigger.isUpdate) {
        JiraStoryTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}