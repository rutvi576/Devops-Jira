/**
 * @description Trigger for sf_devops__Work_Item__c object
 * @author Simran Nandla
 * @date 2025-06-16
 */
trigger WorkItemTrigger on sf_devops__Work_Item__c (before update, after insert, after update, after delete, after undelete) {
    
   if (Trigger.isBefore && Trigger.isUpdate) {
        WorkItemTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUndelete) {
            WorkItemTriggerHandler.handleAfterInsertUndelete(Trigger.new);
        }
        
        if (Trigger.isUpdate) {
            WorkItemTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
        
        if (Trigger.isDelete) {
            WorkItemTriggerHandler.handleAfterDelete(Trigger.old);
        }
    }
}