/**
 * @description Handler class for WorkItemPromoteTrigger
 * @author Salesforce Developer
 * @date 2025
 */
public with sharing class WorkItemPromoteTriggerHandler {
    
     // Retrieve custom metadata configuration
    private static final Jira_Configuration__mdt CONFIG = [
        SELECT SF_FULL_STAGE_NAME__c,SF_READY_TO_UAT_FIELD__c
        FROM Jira_Configuration__mdt
        WHERE DeveloperName = 'Default_Jira_Configuration'
        LIMIT 1
    ];
    /**
     * @description Handles after insert operations
     * @param newRecords List of new Work Item Promote records
     */
    public static void handleAfterInsert(List<sf_devops__Work_Item_Promote__c> newRecords) {
        processWorkItemPromoteRecords(newRecords);
    }
    
    /**
     * @description Handles after update operations
     * @param newRecords List of updated Work Item Promote records
     * @param oldMap Map of old Work Item Promote records
     */
    public static void handleAfterUpdate(List<sf_devops__Work_Item_Promote__c> newRecords, 
                                       Map<Id, sf_devops__Work_Item_Promote__c> oldMap) {
        
        List<sf_devops__Work_Item_Promote__c> recordsToProcess = new List<sf_devops__Work_Item_Promote__c>();
        
        // Only process records where Pipeline Stage has changed
        for (sf_devops__Work_Item_Promote__c newRecord : newRecords) {
            sf_devops__Work_Item_Promote__c oldRecord = oldMap.get(newRecord.Id);
            
            if (newRecord.sf_devops__Pipeline_Stage__c != oldRecord.sf_devops__Pipeline_Stage__c) {
                recordsToProcess.add(newRecord);
            }
        }
        
        if (!recordsToProcess.isEmpty()) {
            processWorkItemPromoteRecords(recordsToProcess);
        }
    }
    
    /**
     * @description Processes Work Item Promote records and updates related Work Items
     * @param workItemPromoteRecords List of Work Item Promote records to process
     */
    private static void processWorkItemPromoteRecords(List<sf_devops__Work_Item_Promote__c> workItemPromoteRecords) {
        
        // Guard clause for empty list
        if (workItemPromoteRecords == null || workItemPromoteRecords.isEmpty()) {
            return;
        }
        
        Set<Id> pipelineStageIds = new Set<Id>();
        Set<Id> workItemIds = new Set<Id>();
        
        // Collect Pipeline Stage IDs and Work Item IDs
        for (sf_devops__Work_Item_Promote__c record : workItemPromoteRecords) {
            if (record.sf_devops__Pipeline_Stage__c != null) {
                pipelineStageIds.add(record.sf_devops__Pipeline_Stage__c);
            }
            if (record.sf_devops__Work_Item__c != null) {
                workItemIds.add(record.sf_devops__Work_Item__c);
            }
        }
        
        // Query Pipeline Stages to get their names
        Map<Id, sf_devops__Pipeline_Stage__c> pipelineStageMap = getPipelineStageMap(pipelineStageIds);
        
        // Determine which Work Items need to be updated
        Set<Id> workItemsToUpdate = getWorkItemsToUpdate(workItemPromoteRecords, pipelineStageMap);
        
        // Update Work Items
        updateWorkItems(workItemsToUpdate);
    }
    
    /**
     * @description Queries and returns Pipeline Stage records
     * @param pipelineStageIds Set of Pipeline Stage IDs
     * @return Map of Pipeline Stage records
     */
    private static Map<Id, sf_devops__Pipeline_Stage__c> getPipelineStageMap(Set<Id> pipelineStageIds) {
        
        if (pipelineStageIds.isEmpty()) {
            return new Map<Id, sf_devops__Pipeline_Stage__c>();
        }
        
        Map<Id, sf_devops__Pipeline_Stage__c> pipelineStageMap = new Map<Id, sf_devops__Pipeline_Stage__c>();
        
        try {
            pipelineStageMap = new Map<Id, sf_devops__Pipeline_Stage__c>([
                SELECT Id, Name
                FROM sf_devops__Pipeline_Stage__c
                WHERE Id IN :pipelineStageIds
                WITH SECURITY_ENFORCED
            ]);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error querying Pipeline Stages: ' + e.getMessage());
        }
        
        return pipelineStageMap;
    }
    
    /**
     * @description Determines which Work Items need to be updated based on Pipeline Stage name
     * @param workItemPromoteRecords List of Work Item Promote records
     * @param pipelineStageMap Map of Pipeline Stage records
     * @return Set of Work Item IDs to update
     */
    private static Set<Id> getWorkItemsToUpdate(List<sf_devops__Work_Item_Promote__c> workItemPromoteRecords,
                                              Map<Id, sf_devops__Pipeline_Stage__c> pipelineStageMap) {
        
        Set<Id> workItemsToUpdate = new Set<Id>();
        
        for (sf_devops__Work_Item_Promote__c record : workItemPromoteRecords) {
            
            // Check if Pipeline Stage exists and has name 'FULL'
            if (record.sf_devops__Pipeline_Stage__c != null && 
                pipelineStageMap.containsKey(record.sf_devops__Pipeline_Stage__c)) {
                
                sf_devops__Pipeline_Stage__c pipelineStage = pipelineStageMap.get(record.sf_devops__Pipeline_Stage__c);
                
                if (CONFIG.SF_FULL_STAGE_NAME__c.equals(pipelineStage.Name) && record.sf_devops__Work_Item__c != null) {
                    workItemsToUpdate.add(record.sf_devops__Work_Item__c);
                }
            }
        }
        
        return workItemsToUpdate;
    }
    
    /**
     * @description Updates Work Item records to set Ready to UAT checkbox to true
     * @param workItemIds Set of Work Item IDs to update
     */
    private static void updateWorkItems(Set<Id> workItemIds) {
        
        if (workItemIds.isEmpty()) {
            return;
        }
        
        List<sf_devops__Work_Item__c> workItemsToUpdate = new List<sf_devops__Work_Item__c>();
        
        // Create Work Item records for update
        for (Id workItemId : workItemIds) {
            sf_devops__Work_Item__c workItem = new sf_devops__Work_Item__c(
                Id = workItemId
            );
            workItem.put(CONFIG.SF_READY_TO_UAT_FIELD__c, true);
            workItemsToUpdate.add(workItem);
        }
        
        // Perform DML operation with error handling
        if (!workItemsToUpdate.isEmpty()) {
            try {
                Database.SaveResult[] results = Database.update(workItemsToUpdate, false);
                
                // Log any errors
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        for (Database.Error error : results[i].getErrors()) {
                            System.debug(LoggingLevel.ERROR, 
                                'Error updating Work Item ' + workItemsToUpdate[i].Id + 
                                ': ' + error.getMessage());
                        }
                    }
                }
                
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Exception updating Work Items: ' + e.getMessage());
            }
        }
    }
}