/**
 * @description Service class for Jira API integration using Custom Metadata for configuration
 * @author Simran Nandla
 * @date 2025-06-16
 * @version 2.6 - Corrected field names to resolve deployment errors and use SF_Status_Closed__c
 */
public class JiraIntegrationService {
    
    // Hardcoded constants
    private static final String CONTENT_TYPE = 'application/json';
    private static final String ACCEPT_TYPE = 'application/json';
    private static final Integer TIMEOUT_SECONDS = 30000;
    private static final String HTTP_METHOD_POST = 'POST';
    private static final String HTTP_METHOD_GET = 'GET';
    private static final String UTF8_ENCODING = 'UTF-8';
    
    // Retrieve custom metadata configuration
    private static final Jira_Configuration__mdt CONFIG1 = [
        SELECT Jira_Base_URL__c, Jira_User_Name__c, Jira_API_Token__c, 
               Jira_QA_Transition_ID__c, Jira_Deployed_On_Staging_Transition_ID__c, 
               Jira_Deployed_On_Prod_Transition_ID__c, Issue_Transition_Endpoint__c,
               SF_In_UAT_Status__c, SF_Status_Closed__c
        FROM Jira_Configuration__mdt
        WHERE DeveloperName = 'Default_Jira_Configuration'
        LIMIT 1
    ];
    
    /**
     * @description Async method to update Jira issue status
     * @param jiraTicketKeys Set of Jira ticket keys to update
     * @param status The target status for the transition
     */
    @Future(callout=true)
    public static void updateJiraIssueStatusAsync(Set<String> jiraTicketKeys, String status) {
        if (jiraTicketKeys == null || jiraTicketKeys.isEmpty() || String.isBlank(status)) {
            System.debug(LoggingLevel.WARN, 'JiraIntegrationService: No ticket keys or status provided');
            return;
        }
        
        // Get Jira configuration from Custom Metadata
        JiraConfiguration config = getJiraConfiguration();
        if (config == null) {
            System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Jira configuration not found or incomplete');
            return;
        }
        
        // Determine transition ID based on status
        String transitionId;
        if (status == CONFIG1.SF_In_UAT_Status__c) {
            transitionId = CONFIG1.Jira_Deployed_On_Staging_Transition_ID__c;
        } else if (status == CONFIG1.SF_Status_Closed__c) {
            transitionId = CONFIG1.Jira_Deployed_On_Prod_Transition_ID__c;
        } else {
            transitionId = CONFIG1.Jira_QA_Transition_ID__c;
        }
        
        // Process each ticket key
        List<String> failedTickets = new List<String>();
        Integer successCount = 0;
        
        for (String ticketKey : jiraTicketKeys) {
            try {
                updateSingleJiraIssue(ticketKey, config, transitionId);
                successCount++;
            } catch (Exception ex) {
                failedTickets.add(ticketKey);
                System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Error updating Jira issue ' + 
                           ticketKey + ': ' + ex.getMessage());
                logJiraIntegrationError(ticketKey, ex.getMessage());
            }
        }
        
        // Log summary
        System.debug(LoggingLevel.INFO, 'JiraIntegrationService: Processed ' + jiraTicketKeys.size() + 
                   ' tickets for status ' + status + '. Success: ' + successCount + ', Failed: ' + failedTickets.size());
    }
    
    /**
     * @description Synchronous method to update a single Jira issue (for testing or immediate updates)
     * @param ticketKey Single Jira ticket key to update
     * @param status The target status for the transition
     * @return Boolean indicating success
     */
    public static Boolean updateJiraIssueStatusSync(String ticketKey, String status) {
        if (String.isBlank(ticketKey) || String.isBlank(status)) {
            System.debug(LoggingLevel.WARN, 'JiraIntegrationService: Empty ticket key or status provided');
            return false;
        }
        
        JiraConfiguration config = getJiraConfiguration();
        if (config == null) {
            System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Jira configuration not found');
            return false;
        }
        
        String transitionId;
        if (status == CONFIG1.SF_In_UAT_Status__c) {
            transitionId = CONFIG1.Jira_Deployed_On_Staging_Transition_ID__c;
        } else if (status == CONFIG1.SF_Status_Closed__c) {
            transitionId = CONFIG1.Jira_Deployed_On_Prod_Transition_ID__c;
        } else {
            transitionId = CONFIG1.Jira_QA_Transition_ID__c;
        }
        
        try {
            updateSingleJiraIssue(ticketKey, config, transitionId);
            return true;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Error updating Jira issue ' + 
                       ticketKey + ': ' + ex.getMessage());
            logJiraIntegrationError(ticketKey, ex.getMessage());
            return false;
        }
    }
    
    /**
     * @description Update single Jira issue status
     * @param ticketKey Jira ticket key
     * @param config Jira configuration
     * @param transitionId The transition ID for the status change
     */
    @TestVisible
    private static void updateSingleJiraIssue(String ticketKey, JiraConfiguration config, String transitionId) {
        // Validate inputs
        if (String.isBlank(ticketKey) || config == null || String.isBlank(transitionId)) {
            throw new JiraIntegrationException('Invalid ticket key, configuration, or transition ID');
        }
        
        // URL encode the ticket key for safety
        String encodedTicketKey = EncodingUtil.urlEncode(ticketKey, UTF8_ENCODING);
        
        // Construct endpoint URL
        String endpoint = config.baseUrl + String.format(config.issueTransitionEndpoint, 
                                                        new List<String>{encodedTicketKey});
        
        // Create HTTP request
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(HTTP_METHOD_POST);
        request.setHeader('Content-Type', CONTENT_TYPE);
        request.setHeader('Accept', ACCEPT_TYPE);
        request.setHeader('Authorization', config.basicAuth);
        request.setTimeout(TIMEOUT_SECONDS);
        
        // Create request body for transition
        Map<String, Object> requestBody = new Map<String, Object>{
            'fields' => new Map<String, Object>(),
            'transition' => new Map<String, Object>{
                'id' => transitionId
            }
        };
        
        request.setBody(JSON.serialize(requestBody));
        
        // Make HTTP callout
        Http http = new Http();
        HttpResponse response = http.send(request);
        
        // Handle response
        handleHttpResponse(response, ticketKey);
    }
    
    /**
     * @description Handle HTTP response from Jira API
     * @param response HttpResponse from Jira API
     * @param ticketKey Jira ticket key for logging
     */
    @TestVisible
    private static void handleHttpResponse(HttpResponse response, String ticketKey) {
        Integer statusCode = response.getStatusCode();
        
        if (statusCode >= 200 && statusCode < 300) {
            System.debug(LoggingLevel.INFO, 'JiraIntegrationService: Successfully updated Jira issue: ' + ticketKey);
        } else {
            String errorMsg = 'Failed to update Jira issue ' + ticketKey + 
                            '. Status Code: ' + statusCode + 
                            ', Status: ' + response.getStatus() +
                            ', Response Body: ' + response.getBody();
            
            System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: ' + errorMsg);
            
            // Throw specific exception based on status code
            if (statusCode == 401) {
                throw new JiraIntegrationException('Authentication failed for Jira API. Please check credentials.');
            } else if (statusCode == 403) {
                throw new JiraIntegrationException('Access forbidden. Check user permissions for ticket: ' + ticketKey);
            } else if (statusCode == 404) {
                throw new JiraIntegrationException('Jira issue not found: ' + ticketKey);
            } else if (statusCode >= 500) {
                throw new JiraIntegrationException('Jira server error. Please try again later.');
            } else {
                throw new JiraIntegrationException(errorMsg);
            }
        }
    }
    
    /**
     * @description Get Jira configuration from Custom Metadata
     * @return JiraConfiguration wrapper class with authentication details
     */
    @TestVisible
    private static JiraConfiguration getJiraConfiguration() {
        try {
            // Validate required configuration
            if (String.isBlank(CONFIG1.Jira_Base_URL__c) || String.isBlank(CONFIG1.Jira_User_Name__c) || 
                String.isBlank(CONFIG1.Jira_API_Token__c)) {
                System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Missing required Jira configuration in Custom Metadata');
                return null;
            }
            
            // Ensure base URL doesn't end with slash
            String baseUrl = CONFIG1.Jira_Base_URL__c;
            if (baseUrl.endsWith('/')) {
                baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
            }
            
            // Create basic auth header
            String basicAuth = 'Basic ' + EncodingUtil.base64Encode(
                Blob.valueOf(CONFIG1.Jira_User_Name__c + ':' + CONFIG1.Jira_API_Token__c)
            );
            
            return new JiraConfiguration(
                baseUrl,
                basicAuth,
                CONFIG1.Jira_QA_Transition_ID__c,
                CONFIG1.Jira_Deployed_On_Staging_Transition_ID__c,
                CONFIG1.Jira_Deployed_On_Prod_Transition_ID__c,
                CONFIG1.Issue_Transition_Endpoint__c,
                CONFIG1.SF_Status_Closed__c
            );
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Error retrieving Jira configuration: ' + ex.getMessage());
            return null;
        }
    }
    
    /**
     * @description Test Jira connectivity and authentication
     * @return Boolean indicating if connection is successful
     */
    public static Boolean testJiraConnection() {
        JiraConfiguration config = getJiraConfiguration();
        if (config == null) {
            return false;
        }
        
        try {
            // Make a simple GET request to test connectivity
            HttpRequest request = new HttpRequest();
            request.setEndpoint(config.baseUrl + '/rest/api/3/myself');
            request.setMethod(HTTP_METHOD_GET);
            request.setHeader('Authorization', config.basicAuth);
            request.setHeader('Accept', ACCEPT_TYPE);
            request.setTimeout(TIMEOUT_SECONDS);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            return response.getStatusCode() == 200;
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Connection test failed: ' + ex.getMessage());
            return false;
        }
    }
    
    /**
     * @description Log Jira integration errors for monitoring and debugging
     * @param ticketKey Jira ticket key that failed
     * @param errorMessage Error message
     */
    @TestVisible
    private static void logJiraIntegrationError(String ticketKey, String errorMessage) {
        try {
            // Create error log record - assuming you have a custom object for logging
            /*Jira_Integration_Log__c logRecord = new Jira_Integration_Log__c(
                Ticket_Key__c = ticketKey,
                Error_Message__c = errorMessage.length() > 255 ? 
                                  errorMessage.substring(0, 255) : errorMessage,
                Full_Error_Message__c = errorMessage,
                Timestamp__c = System.now(),
                Operation_Type__c = 'Status Update',
                User_Id__c = UserInfo.getUserId(),
                Organization_Id__c = UserInfo.getOrganizationId()
            );
            
            Database.SaveResult result = Database.insert(logRecord, false);
            
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Failed to insert error log: ' + 
                           result.getErrors()[0].getMessage());
            }*/
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'JiraIntegrationService: Failed to log Jira integration error: ' + 
                       ex.getMessage());
        }
    }
    
    /**
     * @description Wrapper class for Jira configuration using Custom Metadata
     */
    public class JiraConfiguration {
        public String baseUrl { get; set; }
        public String basicAuth { get; set; }
        public String qaTransitionId { get; set; }
        public String deployedOnStagingTransitionId { get; set; }
        public String deployedOnProdTransitionId { get; set; }
        public String issueTransitionEndpoint { get; set; }
        public String statusClosed { get; set; }
        
        public JiraConfiguration(String baseUrl, String basicAuth, String qaTransitionId,
                                String deployedOnStagingTransitionId, String deployedOnProdTransitionId,
                                String issueTransitionEndpoint, String statusClosed) {
            this.baseUrl = baseUrl;
            this.basicAuth = basicAuth;
            this.qaTransitionId = qaTransitionId;
            this.deployedOnStagingTransitionId = deployedOnStagingTransitionId;
            this.deployedOnProdTransitionId = deployedOnProdTransitionId;
            this.issueTransitionEndpoint = issueTransitionEndpoint;
            this.statusClosed = statusClosed;
        }
    }
    
    /**
     * @description Custom exception class for Jira integration operations
     */
    public class JiraIntegrationException extends Exception {}
}