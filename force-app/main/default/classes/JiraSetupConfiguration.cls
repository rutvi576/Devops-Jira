/**
* @File Name : JiraSetupConfiguration.cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : July 14, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | July 14, 2025 |   | Initial Version
**/

public class JiraSetupConfiguration {
	@AuraEnabled
	public static void LightningStudio(){
		System.debug('Lightning Studio');
	}

	// Retrieve custom metadata configuration
    private static final Jira_Configuration__mdt CONFIG = getJiraConfiguration();

    /**
     * @description Retrieve Jira configuration from custom metadata
     * @return Jira_Configuration__mdt record
     */
    private static Jira_Configuration__mdt getJiraConfiguration() {
        try {
            Jira_Configuration__mdt config = [
                SELECT Jira_Base_URL__c, Jira_API_Endpoint__c, Request_Timeout__c, Max_Results__c,
                       Default_User_ID__c, Work_Item_Creation_Field__c, Issue_Type_Story__c,
                       Issue_Type_Subtask__c, Issue_Type_Epic__c, Issue_Type_Task__c,
                       Parent_Status__c, Sub_Task_status__c, Assignee_Field__c, 
                       Error_Blank_Project_Key__c, Error_Project_Not_Found__c, 
                       Jira_Fields__c, Jira_User_Name__c, Jira_API_Token__c
                FROM Jira_Configuration__mdt
                WHERE DeveloperName = 'Default_Jira_Configuration'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return config;
        } catch (QueryException ex) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving Jira configuration: ' + ex.getMessage());
            throw new AuraHandledException('Jira configuration not found: ' + ex.getMessage());
        }
    }

	// Method to verify Jira credentials and fetch user profile
    @AuraEnabled
    public static Map<String, Object> verifyJiraCredentials(String username, String apiToken) {
        try {
            // Build HTTP request
            HttpRequest request = buildJiraUserProfileRequest(username, apiToken);
            Http http = new Http();
            HttpResponse response = http.send(request);

            Map<String, Object> result = new Map<String, Object>();
            
            if (response.getStatusCode() == 200) {
                // Parse the response to extract user profile data
                Map<String, Object> userProfile = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                result.put('success', true);
                result.put('userProfile', userProfile);
            } else {
                result.put('success', false);
                result.put('error', 'Invalid credentials or Jira API error: ' + response.getStatus());
            }
            return result;
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => 'Error verifying credentials: ' + e.getMessage()
            };
        }
    }

    // Helper method to build Jira user profile request
    private static HttpRequest buildJiraUserProfileRequest(String username, String apiToken) {
        String basicAuth = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(username + ':' + apiToken));
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(CONFIG.Jira_Base_URL__c+'/rest/api/3/myself'); // Replace with your Jira instance URL
        request.setHeader('Authorization', basicAuth);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setMethod('GET');
        request.setTimeout(120000); // 120 seconds timeout
        return request;
    }
}