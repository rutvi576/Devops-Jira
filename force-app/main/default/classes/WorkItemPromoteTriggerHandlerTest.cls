/**
 * @description Test class for WorkItemPromoteTriggerHandler
 * @author Salesforce Developer
 * @date 2025
 */
@IsTest
private class WorkItemPromoteTriggerHandlerTest {
    
    private static final String FULL_STAGE_NAME = 'FULL';
    private static final String OTHER_STAGE_NAME = 'DEVELOPMENT';
    private static final String READY_TO_UAT_FIELD = 'Ready_to_UAT__c'; // Update with actual API name
    
    /**
     * @description Test data setup
     */
    @TestSetup
    static void setupTestData() {
        
        // Create Pipeline Stages
        List<sf_devops__Pipeline_Stage__c> pipelineStages = new List<sf_devops__Pipeline_Stage__c>();
        
        sf_devops__Pipeline_Stage__c fullStage = new sf_devops__Pipeline_Stage__c(
            Name = FULL_STAGE_NAME
        );
        pipelineStages.add(fullStage);
        
        sf_devops__Pipeline_Stage__c otherStage = new sf_devops__Pipeline_Stage__c(
            Name = OTHER_STAGE_NAME
        );
        pipelineStages.add(otherStage);
        
        insert pipelineStages;
        
        // Create Work Items
        List<sf_devops__Work_Item__c> workItems = new List<sf_devops__Work_Item__c>();
        
        sf_devops__Work_Item__c workItem1 = new sf_devops__Work_Item__c(
            sf_devops__Subject__c = 'Test Work Item 1'
        );
        workItem1.put(READY_TO_UAT_FIELD, false);
        workItems.add(workItem1);
        
        sf_devops__Work_Item__c workItem2 = new sf_devops__Work_Item__c(
            sf_devops__Subject__c = 'Test Work Item 2'
        );
        workItem2.put(READY_TO_UAT_FIELD, false);
        workItems.add(workItem2);
        
        insert workItems;
    }
    
    /**
     * @description Test Work Item Promote insert with FULL stage name
     */
    @IsTest
    static void testWorkItemPromoteInsertWithFullStage() {
        
        // Get test data
        sf_devops__Pipeline_Stage__c fullStage = [SELECT Id FROM sf_devops__Pipeline_Stage__c WHERE Name = :FULL_STAGE_NAME LIMIT 1];
        sf_devops__Work_Item__c workItem = [SELECT Id FROM sf_devops__Work_Item__c WHERE Name = 'Test Work Item 1' LIMIT 1];
        
        Test.startTest();
        
        // Create Work Item Promote with FULL stage
        sf_devops__Work_Item_Promote__c workItemPromote = new sf_devops__Work_Item_Promote__c(
            sf_devops__Pipeline_Stage__c = fullStage.Id,
            sf_devops__Work_Item__c = workItem.Id
        );
        
        insert workItemPromote;
        
        Test.stopTest();
        
        // Verify Work Item was updated
        sf_devops__Work_Item__c updatedWorkItem = (sf_devops__Work_Item__c) Database.query(
            'SELECT Id, ' + READY_TO_UAT_FIELD + ' FROM sf_devops__Work_Item__c WHERE Id = :workItem.Id'
        )[0];
        
        System.assertEquals(true, updatedWorkItem.get(READY_TO_UAT_FIELD), 
            'Work Item Ready to UAT should be set to true when Pipeline Stage is FULL');
    }
    
    /**
     * @description Test Work Item Promote insert with non-FULL stage name
     */
    @IsTest
    static void testWorkItemPromoteInsertWithNonFullStage() {
        
        // Get test data
        sf_devops__Pipeline_Stage__c otherStage = [SELECT Id FROM sf_devops__Pipeline_Stage__c WHERE Name = :OTHER_STAGE_NAME LIMIT 1];
        sf_devops__Work_Item__c workItem = [SELECT Id FROM sf_devops__Work_Item__c WHERE Name = 'Test Work Item 1' LIMIT 1];
        
        Test.startTest();
        
        // Create Work Item Promote with non-FULL stage
        sf_devops__Work_Item_Promote__c workItemPromote = new sf_devops__Work_Item_Promote__c(
            sf_devops__Pipeline_Stage__c = otherStage.Id,
            sf_devops__Work_Item__c = workItem.Id
        );
        
        insert workItemPromote;
        
        Test.stopTest();
        
        // Verify Work Item was NOT updated
        sf_devops__Work_Item__c updatedWorkItem = (sf_devops__Work_Item__c) Database.query(
            'SELECT Id, ' + READY_TO_UAT_FIELD + ' FROM sf_devops__Work_Item__c WHERE Id = :workItem.Id'
        )[0];
        
        System.assertEquals(false, updatedWorkItem.get(READY_TO_UAT_FIELD), 
            'Work Item Ready to UAT should remain false when Pipeline Stage is not FULL');
    }
    
    /**
     * @description Test Work Item Promote update from non-FULL to FULL stage
     */
    @IsTest
    static void testWorkItemPromoteUpdateToFullStage() {
        
        // Get test data
        sf_devops__Pipeline_Stage__c fullStage = [SELECT Id FROM sf_devops__Pipeline_Stage__c WHERE Name = :FULL_STAGE_NAME LIMIT 1];
        sf_devops__Pipeline_Stage__c otherStage = [SELECT Id FROM sf_devops__Pipeline_Stage__c WHERE Name = :OTHER_STAGE_NAME LIMIT 1];
        sf_devops__Work_Item__c workItem = [SELECT Id FROM sf_devops__Work_Item__c WHERE Name = 'Test Work Item 1' LIMIT 1];
        
        // Create Work Item Promote with non-FULL stage initially
        sf_devops__Work_Item_Promote__c workItemPromote = new sf_devops__Work_Item_Promote__c(
            sf_devops__Pipeline_Stage__c = otherStage.Id,
            sf_devops__Work_Item__c = workItem.Id
        );
        insert workItemPromote;
        
        Test.startTest();
        
        // Update to FULL stage
        workItemPromote.sf_devops__Pipeline_Stage__c = fullStage.Id;
        update workItemPromote;
        
        Test.stopTest();
        
        // Verify Work Item was updated
        sf_devops__Work_Item__c updatedWorkItem = (sf_devops__Work_Item__c) Database.query(
            'SELECT Id, ' + READY_TO_UAT_FIELD + ' FROM sf_devops__Work_Item__c WHERE Id = :workItem.Id'
        )[0];
        
        System.assertEquals(true, updatedWorkItem.get(READY_TO_UAT_FIELD), 
            'Work Item Ready to UAT should be set to true when Pipeline Stage is updated to FULL');
    }
    
    /**
     * @description Test Work Item Promote update without Pipeline Stage change
     */
    @IsTest
    static void testWorkItemPromoteUpdateWithoutStageChange() {
        
        // Get test data
        sf_devops__Pipeline_Stage__c otherStage = [SELECT Id FROM sf_devops__Pipeline_Stage__c WHERE Name = :OTHER_STAGE_NAME LIMIT 1];
        sf_devops__Work_Item__c workItem = [SELECT Id FROM sf_devops__Work_Item__c WHERE Name = 'Test Work Item 1' LIMIT 1];
        
        // Create Work Item Promote
        sf_devops__Work_Item_Promote__c workItemPromote = new sf_devops__Work_Item_Promote__c(
            sf_devops__Pipeline_Stage__c = otherStage.Id,
            sf_devops__Work_Item__c = workItem.Id
        );
        insert workItemPromote;
        
        Test.startTest();
        
        // Update without changing Pipeline Stage (e.g., update a different field)
        // Note: You would update another field here if available
        update workItemPromote;
        
        Test.stopTest();
        
        // Verify Work Item was NOT updated again
        sf_devops__Work_Item__c updatedWorkItem = (sf_devops__Work_Item__c) Database.query(
            'SELECT Id, ' + READY_TO_UAT_FIELD + ' FROM sf_devops__Work_Item__c WHERE Id = :workItem.Id'
        )[0];
        
        System.assertEquals(false, updatedWorkItem.get(READY_TO_UAT_FIELD), 
            'Work Item Ready to UAT should remain false when Pipeline Stage is not changed');
    }
    
    /**
     * @description Test bulk operations
     */
    @IsTest
    static void testBulkOperations() {
        
        // Get test data
        sf_devops__Pipeline_Stage__c fullStage = [SELECT Id FROM sf_devops__Pipeline_Stage__c WHERE Name = :FULL_STAGE_NAME LIMIT 1];
        List<sf_devops__Work_Item__c> workItems = [SELECT Id FROM sf_devops__Work_Item__c];
        
        Test.startTest();
        
        // Create multiple Work Item Promotes
        List<sf_devops__Work_Item_Promote__c> workItemPromotes = new List<sf_devops__Work_Item_Promote__c>();
        
        for (sf_devops__Work_Item__c workItem : workItems) {
            sf_devops__Work_Item_Promote__c workItemPromote = new sf_devops__Work_Item_Promote__c(
                sf_devops__Pipeline_Stage__c = fullStage.Id,
                sf_devops__Work_Item__c = workItem.Id
            );
            workItemPromotes.add(workItemPromote);
        }
        
        insert workItemPromotes;
        
        Test.stopTest();
        
        // Verify all Work Items were updated
        List<sf_devops__Work_Item__c> updatedWorkItems = Database.query(
            'SELECT Id, ' + READY_TO_UAT_FIELD + ' FROM sf_devops__Work_Item__c WHERE Id IN :workItems'
        );
        
        for (sf_devops__Work_Item__c workItem : updatedWorkItems) {
            System.assertEquals(true, workItem.get(READY_TO_UAT_FIELD), 
                'All Work Items should have Ready to UAT set to true');
        }
    }
    
    /**
     * @description Test null safety
     */
    @IsTest
    static void testNullSafety() {
        
        Test.startTest();
        
        // Test with null Pipeline Stage
        sf_devops__Work_Item__c workItem = [SELECT Id FROM sf_devops__Work_Item__c LIMIT 1];
        
        sf_devops__Work_Item_Promote__c workItemPromote = new sf_devops__Work_Item_Promote__c(
            sf_devops__Work_Item__c = workItem.Id
            // sf_devops__Pipeline_Stage__c is null
        );
        
        // This should not cause an exception
        insert workItemPromote;
        
        Test.stopTest();
        
        // Verify Work Item was NOT updated
        sf_devops__Work_Item__c updatedWorkItem = (sf_devops__Work_Item__c) Database.query(
            'SELECT Id, ' + READY_TO_UAT_FIELD + ' FROM sf_devops__Work_Item__c WHERE Id = :workItem.Id'
        )[0];
        
        System.assertEquals(false, updatedWorkItem.get(READY_TO_UAT_FIELD), 
            'Work Item Ready to UAT should remain false when Pipeline Stage is null');
    }
}