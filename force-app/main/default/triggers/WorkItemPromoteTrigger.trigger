/**
 * @description Trigger on sf_devops__Work_Item_Promote__c object
 * @author Salesforce Developer
 * @date 2025
 */
trigger WorkItemPromoteTrigger on sf_devops__Work_Item_Promote__c (after insert, after update) {
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            WorkItemPromoteTriggerHandler.handleAfterInsert(Trigger.new);
        }
        
        if (Trigger.isUpdate) {
            WorkItemPromoteTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}