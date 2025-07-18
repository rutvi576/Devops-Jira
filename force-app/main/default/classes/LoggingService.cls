/**
 * @description Utility class for centralized logging functionality
 * @author Salesforce Developer
 * @date 2025-06-19
 */
public with sharing class LoggingService {
    
    private static final String LOG_LEVEL_ERROR = 'ERROR';
    private static final String LOG_LEVEL_INFO = 'INFO';
    private static final String LOG_LEVEL_DEBUG = 'DEBUG';
    
    /**
     * @description Logs error messages with exception details
     * @param className Name of the class where error occurred
     * @param message Error message description
     * @param ex Exception object (can be null)
     */
    public static void logError(String className, String message, Exception ex) {
        String errorDetails = buildErrorMessage(className, message, ex);
        System.debug(LoggingLevel.ERROR, errorDetails);
        
        // Optional: Insert into custom logging object if available
        // insertLogRecord(LOG_LEVEL_ERROR, className, errorDetails);
    }
    
    /**
     * @description Logs informational messages
     * @param className Name of the class
     * @param message Info message
     */
    public static void logInfo(String className, String message) {
        String infoMessage = buildInfoMessage(className, message);
        System.debug(LoggingLevel.INFO, infoMessage);
        
        // Optional: Insert into custom logging object if available
        // insertLogRecord(LOG_LEVEL_INFO, className, infoMessage);
    }
    
    /**
     * @description Logs debug messages
     * @param className Name of the class
     * @param message Debug message
     */
    public static void logDebug(String className, String message) {
        String debugMessage = buildDebugMessage(className, message);
        System.debug(LoggingLevel.DEBUG, debugMessage);
    }
    
    /**
     * @description Builds formatted error message with exception details
     * @param className Name of the class
     * @param message Error message
     * @param ex Exception object
     * @return Formatted error message string
     */
    private static String buildErrorMessage(String className, String message, Exception ex) {
        String errorMsg = '[' + LOG_LEVEL_ERROR + '] ' + className + ': ' + message;
        
        if (ex != null) {
            errorMsg += ' | Exception: ' + ex.getTypeName() + 
                       ' | Message: ' + ex.getMessage() + 
                       ' | Line: ' + ex.getLineNumber() + 
                       ' | Stack: ' + ex.getStackTraceString();
        }
        
        return errorMsg;
    }
    
    /**
     * @description Builds formatted info message
     * @param className Name of the class
     * @param message Info message
     * @return Formatted info message string
     */
    private static String buildInfoMessage(String className, String message) {
        return '[' + LOG_LEVEL_INFO + '] ' + className + ': ' + message;
    }
    
    /**
     * @description Builds formatted debug message
     * @param className Name of the class
     * @param message Debug message
     * @return Formatted debug message string
     */
    private static String buildDebugMessage(String className, String message) {
        return '[' + LOG_LEVEL_DEBUG + '] ' + className + ': ' + message;
    }
    
    /**
     * @description Optional method to insert log records into custom object
     * Uncomment and customize based on your logging object structure
     * @param level Log level
     * @param className Class name
     * @param message Log message
     */
    /*
    private static void insertLogRecord(String level, String className, String message) {
        try {
            Log__c logRecord = new Log__c(
                Level__c = level,
                Class_Name__c = className,
                Message__c = message.left(32000), // Ensure message fits in field
                Timestamp__c = Datetime.now()
            );
            insert logRecord;
        } catch (Exception ex) {
            // Fallback to system debug if custom logging fails
            System.debug(LoggingLevel.ERROR, 'LoggingService: Failed to insert log record - ' + ex.getMessage());
        }
    }
    */
}