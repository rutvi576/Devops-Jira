/**
 * @description REST Resource to handle Jira webhook events for status updates
 * @author Salesforce Developer
 * @date 2025-06-19
 * @version 1.1 - Added support for UAT Complete and READYFORPRODUCTIONDEPLOYMENT status updates
 */
@RestResource(urlMapping='/jira/webhook/*')
global without sharing class JiraWebhookHandler {
    
    private static final String JIRA_EVENT_TYPE = 'jira:issue_updated';
    private static final String STATUS_FIELD = 'status';
    private static final String TARGET_FROM_STATUS_QA = 'In QA';
    private static final String TARGET_TO_STATUS_QA = 'Testing Complete';
    private static final String TARGET_TO_STATUS_UAT = 'UAT COMPLETE';
    private static final String TARGET_TO_STATUS_PROD = 'ReadyForProductionDeployment';
    private static final String SALESFORCE_STATUS_QA = 'TESTING COMPLETED';
    private static final String SALESFORCE_STATUS_UAT = 'UAT COMPLETE';
    private static final String SALESFORCE_STATUS_PROD = 'READY FOR PROD';
    
    /**
     * @description Handles POST requests from Jira webhooks
     * @return JiraWebhookResponse wrapper with success/error details
     */
    @HttpPost
    global static JiraWebhookResponse handleWebhook() {
        try {
            System.debug('=== JIRA WEBHOOK HANDLER START ===');
            RestRequest request = RestContext.request;
            
            if (request?.requestBody == null) {
                System.debug('ERROR: Request body is null or empty');
                return createErrorResponse('Request body is empty', 'EMPTY_REQUEST');
            }
            
            String requestBody = request.requestBody.toString();
            System.debug('RAW REQUEST BODY: ' + requestBody);
            System.debug('REQUEST BODY LENGTH: ' + requestBody.length());
            
            JiraWebhookPayload payload = parseWebhookPayload(requestBody);
            System.debug('PARSED PAYLOAD: ' + JSON.serializePretty(payload));
            
            // Debug webhook event validation
            System.debug('VALIDATING WEBHOOK EVENT...');
            System.debug('Event Type from Payload: ' + (payload?.webhookEvent != null ? payload.webhookEvent : 'NULL'));
            System.debug('Expected Event Type: ' + JIRA_EVENT_TYPE);
            System.debug('Event Type Match: ' + (payload?.webhookEvent == JIRA_EVENT_TYPE));
            
            if (!isValidWebhookEvent(payload)) {
                System.debug('WEBHOOK EVENT NOT VALID - IGNORING');
                return createSuccessResponse('Webhook event ignored - not a relevant status update', null);
            }
            
            System.debug('WEBHOOK EVENT IS VALID - PROCEEDING');
            
            // Debug issue key extraction
            String issueKey = payload?.issue?.key;
            System.debug('EXTRACTED ISSUE KEY: ' + issueKey);
            
            List<Jira_Story__c> jiraStories = getJiraStoriesByTicketKey(issueKey);
            System.debug('FOUND JIRA STORIES COUNT: ' + jiraStories.size());
            
            for (Integer i = 0; i < jiraStories.size(); i++) {
                Jira_Story__c story = jiraStories[i];
                System.debug('STORY ' + (i+1) + ' - ID: ' + story.Id);
                System.debug('STORY ' + (i+1) + ' - Name: ' + story.Name);
                System.debug('STORY ' + (i+1) + ' - Ticket Key: ' + story.Jira_Ticket_Key__c);
                System.debug('STORY ' + (i+1) + ' - Current Status: ' + story.Status__c);
            }
            
            if (jiraStories.isEmpty()) {
                System.debug('ERROR: No Jira Story found with ticket key: ' + issueKey);
                return createErrorResponse('No Jira Story found with ticket key: ' + issueKey, 'RECORD_NOT_FOUND');
            }
            
            List<Jira_Story__c> updatedStories = updateJiraStoryStatus(jiraStories, payload);
            System.debug('SUCCESSFULLY UPDATED STORIES COUNT: ' + updatedStories.size());
            
            System.debug('=== JIRA WEBHOOK HANDLER END - SUCCESS ===');
            return createSuccessResponse('Successfully updated ' + updatedStories.size() + ' Jira Story records', updatedStories);
            
        } catch (JSONException jsonEx) {
            System.debug('JSON EXCEPTION: ' + jsonEx.getMessage());
            System.debug('JSON EXCEPTION STACK TRACE: ' + jsonEx.getStackTraceString());
            LoggingService.logError('JiraWebhookHandler', 'JSON parsing failed', jsonEx);
            return createErrorResponse('Invalid JSON format: ' + jsonEx.getMessage(), 'JSON_PARSE_ERROR');
        } catch (DmlException dmlEx) {
            System.debug('DML EXCEPTION: ' + dmlEx.getMessage());
            System.debug('DML EXCEPTION STACK TRACE: ' + dmlEx.getStackTraceString());
            LoggingService.logError('JiraWebhookHandler', 'DML operation failed', dmlEx);
            return createErrorResponse('Database operation failed: ' + dmlEx.getMessage(), 'DML_ERROR');
        } catch (Exception ex) {
            System.debug('GENERAL EXCEPTION: ' + ex.getMessage());
            System.debug('GENERAL EXCEPTION STACK TRACE: ' + ex.getStackTraceString());
            LoggingService.logError('JiraWebhookHandler', 'Unexpected error occurred', ex);
            return createErrorResponse('Unexpected error: ' + ex.getMessage(), 'UNEXPECTED_ERROR');
        }
    }
    
    /**
     * @description Parses the webhook payload JSON into a structured object
     * @param requestBody Raw JSON string from webhook
     * @return JiraWebhookPayload parsed payload object
     */
    private static JiraWebhookPayload parseWebhookPayload(String requestBody) {
        System.debug('PARSING JSON PAYLOAD...');
        try {
            JiraWebhookPayload payload = (JiraWebhookPayload) JSON.deserialize(requestBody, JiraWebhookPayload.class);
            System.debug('JSON PARSING SUCCESSFUL');
            return payload;
        } catch (Exception ex) {
            System.debug('JSON PARSING FAILED: ' + ex.getMessage());
            throw ex;
        }
    }
    
    /**
     * @description Validates if the webhook event should be processed
     * @param payload Parsed webhook payload
     * @return Boolean indicating if event is valid for processing
     */
    private static Boolean isValidWebhookEvent(JiraWebhookPayload payload) {
        System.debug('VALIDATING WEBHOOK EVENT...');
        
        if (payload?.webhookEvent == null || !payload.webhookEvent.equalsIgnoreCase(JIRA_EVENT_TYPE)) {
            System.debug('INVALID: Event type mismatch. Got: ' + payload?.webhookEvent + ', Expected: ' + JIRA_EVENT_TYPE);
            return false;
        }
        System.debug('VALID: Event type matches');
        
        if (payload.changelog?.items == null || payload.changelog.items.isEmpty()) {
            System.debug('INVALID: No changelog items found');
            return false;
        }
        System.debug('VALID: Changelog items found. Count: ' + payload.changelog.items.size());
        
        for (Integer i = 0; i < payload.changelog.items.size(); i++) {
            JiraChangelogItem item = payload.changelog.items[i];
            System.debug('CHANGELOG ITEM ' + (i+1) + ':');
            System.debug('  - Field: ' + item.field);
            System.debug('  - From String: ' + item.fromString);
            System.debug('  - To String: ' + item.toString);
            System.debug('  - From Value: ' + item.fromValue);
            System.debug('  - To Value: ' + item.toValue);
            
            // Use equalsIgnoreCase and trim to handle case sensitivity and whitespace
            Boolean isStatusField = item.field != null && item.field.trim().equalsIgnoreCase(STATUS_FIELD);
            Boolean isQATransition = item.toString != null && item.toString.trim().equalsIgnoreCase(TARGET_TO_STATUS_QA) &&
                                     item.fromString != null && item.fromString.trim().equalsIgnoreCase(TARGET_FROM_STATUS_QA);
            Boolean isUATTransition = item.toString != null && item.toString.trim().equalsIgnoreCase(TARGET_TO_STATUS_UAT);
            Boolean isProdTransition = item.toString != null && item.toString.trim().equalsIgnoreCase(TARGET_TO_STATUS_PROD);
            
            System.debug('  - Is Status Field: ' + isStatusField + ' (Expected: ' + STATUS_FIELD + ', Got: ' + item.field + ')');
            System.debug('  - Is QA Transition: ' + isQATransition + ' (From: ' + TARGET_FROM_STATUS_QA + ', To: ' + TARGET_TO_STATUS_QA + ')');
            System.debug('  - Is UAT Transition: ' + isUATTransition + ' (To: ' + TARGET_TO_STATUS_UAT + ')');
            System.debug('  - Is Prod Transition: ' + isProdTransition + ' (To: ' + TARGET_TO_STATUS_PROD + ')');
            
            if (isStatusField && (isQATransition || isUATTransition || isProdTransition)) {
                System.debug('VALID: Found matching status change in changelog item ' + (i+1));
                return true;
            }
        }
        
        System.debug('INVALID: No matching status change found in any changelog items');
        return false;
    }
    
    /**
     * @description Retrieves Jira Story records by ticket key
     * @param ticketKey Jira issue key (e.g., DEV-35)
     * @return List of matching Jira_Story__c records
     */
    private static List<Jira_Story__c> getJiraStoriesByTicketKey(String ticketKey) {
        System.debug('QUERYING JIRA STORIES...');
        System.debug('TICKET KEY: ' + ticketKey);
        
        if (String.isBlank(ticketKey)) {
            System.debug('TICKET KEY IS BLANK - RETURNING EMPTY LIST');
            return new List<Jira_Story__c>();
        }
        
        List<Jira_Story__c> stories = [
            SELECT Id, Name, Jira_Ticket_Key__c, Status__c 
            FROM Jira_Story__c 
            WHERE Jira_Ticket_Key__c = :ticketKey
            WITH SECURITY_ENFORCED
            LIMIT 100
        ];
        
        System.debug('QUERY EXECUTED. FOUND ' + stories.size() + ' RECORDS');
        System.debug('QUERY: SELECT Id, Name, Jira_Ticket_Key__c, Status__c FROM Jira_Story__c WHERE Jira_Ticket_Key__c = \'' + ticketKey + '\'');
        
        return stories;
    }
    
    /**
     * @description Updates the status of Jira Story records
     * @param jiraStories List of Jira_Story__c records to update
     * @param payload Parsed webhook payload to determine the target status
     * @return List of updated Jira_Story__c records
     */
    private static List<Jira_Story__c> updateJiraStoryStatus(List<Jira_Story__c> jiraStories, JiraWebhookPayload payload) {
        System.debug('UPDATING JIRA STORY STATUS...');
        System.debug('RECORDS TO UPDATE: ' + jiraStories.size());
        
        String targetSalesforceStatus = SALESFORCE_STATUS_QA; // Default to QA status
        for (JiraChangelogItem item : payload.changelog.items) {
            if (item.field != null && item.field.trim().equalsIgnoreCase(STATUS_FIELD)) {
                if (item.toString != null && item.toString.trim().equalsIgnoreCase(TARGET_TO_STATUS_UAT)) {
                    targetSalesforceStatus = SALESFORCE_STATUS_UAT;
                } else if (item.toString != null && item.toString.trim().equalsIgnoreCase(TARGET_TO_STATUS_PROD)) {
                    targetSalesforceStatus = SALESFORCE_STATUS_PROD;
                }
                break; // Exit after finding the relevant status change
            }
        }
        
        for (Integer i = 0; i < jiraStories.size(); i++) {
            Jira_Story__c story = jiraStories[i];
            String oldStatus = story.Status__c;
            story.Status__c = targetSalesforceStatus;
            System.debug('STORY ' + (i+1) + ' STATUS CHANGE: "' + oldStatus + '" -> "' + targetSalesforceStatus + '"');
        }
        
        System.debug('EXECUTING DATABASE UPDATE...');
        Database.SaveResult[] results = Database.update(jiraStories, false);
        List<Jira_Story__c> successfulUpdates = new List<Jira_Story__c>();
        
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult result = results[i];
            Jira_Story__c story = jiraStories[i];
            
            System.debug('UPDATE RESULT ' + (i+1) + ':');
            System.debug('  - Record ID: ' + story.Id);
            System.debug('  - Success: ' + result.isSuccess());
            
            if (result.isSuccess()) {
                System.debug('  - Successfully updated record');
                successfulUpdates.add(story);
            } else {
                System.debug('  - Update failed. Errors:');
                String errorMsg = 'Failed to update record ' + story.Id + ': ';
                for (Database.Error error : result.getErrors()) {
                    System.debug('    * ' + error.getMessage());
                    System.debug('    * Status Code: ' + error.getStatusCode());
                    System.debug('    * Fields: ' + String.join(error.getFields(), ', '));
                    errorMsg += error.getMessage() + ' ';
                }
                LoggingService.logError('JiraWebhookHandler', errorMsg, null);
            }
        }
        
        System.debug('UPDATE COMPLETE. SUCCESSFUL UPDATES: ' + successfulUpdates.size());
        return successfulUpdates;
    }
    
    /**
     * @description Creates a success response wrapper
     * @param message Success message
     * @param updatedRecords List of updated records
     * @return JiraWebhookResponse success response
     */
    private static JiraWebhookResponse createSuccessResponse(String message, List<Jira_Story__c> updatedRecords) {
        System.debug('CREATING SUCCESS RESPONSE: ' + message);
        JiraWebhookResponse response = new JiraWebhookResponse();
        response.success = true;
        response.message = message;
        response.updatedRecords = updatedRecords;
        response.timestamp = Datetime.now();
        System.debug('SUCCESS RESPONSE CREATED: ' + JSON.serializePretty(response));
        return response;
    }
    
    /**
     * @description Creates an error response wrapper
     * @param message Error message
     * @param errorCode Error code identifier
     * @return JiraWebhookResponse error response
     */
    private static JiraWebhookResponse createErrorResponse(String message, String errorCode) {
        System.debug('CREATING ERROR RESPONSE: ' + message + ' (Code: ' + errorCode + ')');
        JiraWebhookResponse response = new JiraWebhookResponse();
        response.success = false;
        response.message = message;
        response.errorCode = errorCode;
        response.timestamp = Datetime.now();
        System.debug('ERROR RESPONSE CREATED: ' + JSON.serializePretty(response));
        return response;
    }
    
    /**
     * @description Wrapper class for webhook response
     */
    global class JiraWebhookResponse {
        public Boolean success { get; set; }
        public String message { get; set; }
        public String errorCode { get; set; }
        public List<Jira_Story__c> updatedRecords { get; set; }
        public Datetime timestamp { get; set; }
    }
    
    /**
     * @description Wrapper classes for parsing Jira webhook payload
     */
    public class JiraWebhookPayload {
        public String webhookEvent { get; set; }
        public JiraIssue issue { get; set; }
        public JiraChangelog changelog { get; set; }
        public String timestamp { get; set; }
        public String issue_event_type_name { get; set; }
        public JiraUser user { get; set; }
    }
    
    public class JiraUser {
        public String self { get; set; }
        public String accountId { get; set; }
        public Map<String, String> avatarUrls { get; set; }
        public String displayName { get; set; }
        public Boolean active { get; set; }
        public String timeZone { get; set; }
        public String accountType { get; set; }
    }
    
    public class JiraChangelog {
        public String id { get; set; }
        public List<JiraChangelogItem> items { get; set; }
    }
    
    public class JiraChangelogItem {
        public String field { get; set; }
        public String fieldId { get; set; }
        public String fieldtype { get; set; }
        public String fromValue { get; set; }
        public String fromString { get; set; }
        public String toValue { get; set; }
        public String toString { get; set; }
    }
    
    public class JiraIssue {
        public String id { get; set; }
        public String key { get; set; }
        public JiraIssueFields fields { get; set; }
    }
    
    public class JiraIssueFields {
        public JiraProject project { get; set; }
        public JiraStatus status { get; set; }
        public String summary { get; set; }
    }
    
    public class JiraProject {
        public String id { get; set; }
        public String key { get; set; }
        public String name { get; set; }
    }
    
    public class JiraStatus {
        public String id { get; set; }
        public String name { get; set; }
    }
}