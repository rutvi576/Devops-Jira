import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import processJiraIssues from '@salesforce/apex/JiraService.processJiraIssues';

/**
 * @description LWC component for Jira integration with modal popup and accordion results view
 * @author Your Name
 * @date 2025-06-13
 */
export default class JiraIntegrationModal extends LightningElement {
    // Public properties
    @api recordId;
    
    // Private tracked properties
    @track isModalOpen = true;
    @track projectKey = '';
    @track isProcessing = false;
    @track processingResult = {};
    @track errorMessages = [];
    @track createdStories = [];
    @track createdWorkItems = [];
    
    // Constants
     COMPONENT_NAME = 'JiraIntegrationModal';
    ERROR_MESSAGES = {
        INVALID_PROJECT_KEY: 'Please enter a valid project key',
        PROCESSING_FAILED: 'Failed to process Jira issues',
        UNEXPECTED_ERROR: 'An unexpected error occurred'
    };
    
    // Computed properties
    get isProcessButtonDisabled() {
        return this.isProcessing || !this.projectKey?.trim();
    }
    
    get hasErrors() {
        return this.errorMessages && this.errorMessages.length > 0;
    }
    
    get showSuccessMessage() {
        return this.processingResult && 
               (this.processingResult.storiesCreated > 0 || this.processingResult.workItemsCreated > 0) &&
               !this.hasErrors;
    }
    
    get showResults() {
        return this.processingResult && 
               (this.processingResult.storiesCreated >= 0 || this.processingResult.workItemsCreated >= 0);
    }
    
    get storiesLabel() {
        const count = this.processingResult?.storiesCreated || 0;
        return `Stories Created (${count})`;
    }
    
    get workItemsLabel() {
        const count = this.processingResult?.workItemsCreated || 0;
        return `Work Items Created (${count})`;
    }
    
    get hasStories() {
        return this.createdStories && this.createdStories.length > 0;
    }
    
    get hasWorkItems() {
        return this.createdWorkItems && this.createdWorkItems.length > 0;
    }
    
    // Lifecycle hooks
    connectedCallback() {
        this.initializeComponent();
    }
    
    disconnectedCallback() {
        this.cleanup();
    }
    
    // Public methods
    @api
openModal() {
    console.log('Opening modal...');
    this.isModalOpen = true;
    this.resetComponentState();
    
    // Debug: Check if modal elements exist after state change
    setTimeout(() => {
        const modalElement = this.template.querySelector('.slds-modal');
        const backdropElement = this.template.querySelector('.slds-backdrop');
        
        console.log('Modal element found:', !!modalElement);
        console.log('Backdrop element found:', !!backdropElement);
        
        if (modalElement) {
            console.log('Modal computed styles:', window.getComputedStyle(modalElement));
            console.log('Modal z-index:', window.getComputedStyle(modalElement).zIndex);
        }
        
        this.focusOnProjectKeyInput();
    }, 50);
}
    
    @api
    closeModal() {
        this.isModalOpen = false;
        this.resetComponentState();
    }
    
    // Event handlers
    handleProjectKeyChange(event) {
        this.projectKey = event.target.value?.trim() || '';
        this.clearErrors();
    }
    
    async handleProcessIssues() {
        if (!this.validateInputs()) {
            return;
        }
        
        await this.processJiraIssuesAsync();
    }
    
    // Private methods
    initializeComponent() {
        this.resetComponentState();
    }
    
    cleanup() {
        // Cleanup any subscriptions or event listeners if needed
        this.resetComponentState();
    }
    
    resetComponentState() {
        this.projectKey = '';
        this.isProcessing = false;
        this.processingResult = {};
        this.errorMessages = [];
        this.createdStories = [];
        this.createdWorkItems = [];
    }
    
    validateInputs() {
        this.clearErrors();
        
        if (!this.projectKey) {
            this.addError(JiraIntegrationModal.ERROR_MESSAGES.INVALID_PROJECT_KEY);
            return false;
        }
        
        return true;
    }
    
    async processJiraIssuesAsync() {
        this.isProcessing = true;
        this.clearErrors();
        
        try {
            const result = await processJiraIssues({ projectKey: this.projectKey });
            
            if (result) {
                this.handleProcessingSuccess(result);
            } else {
                this.addError(JiraIntegrationModal.ERROR_MESSAGES.PROCESSING_FAILED);
            }
        } catch (error) {
            this.handleProcessingError(error);
        } finally {
            this.isProcessing = false;
        }
    }
    
    handleProcessingSuccess(result) {
        this.processingResult = { ...result };
        
        // Process errors if any
        if (result.errors && result.errors.length > 0) {
            this.errorMessages = [...result.errors];
        }
        
        // Create mock data for demonstration (in real scenario, you'd get this from the result)
        this.createMockResultData(result);
        
        // Show success toast
        if (this.showSuccessMessage) {
            this.showToast(
                'Success',
                `Processing completed! Created ${result.storiesCreated} stories and ${result.workItemsCreated} work items.`,
                'success'
            );
        }
    }
    
    handleProcessingError(error) {
        console.error(`${JiraIntegrationModal.COMPONENT_NAME}: Processing error:`, error);
        
        const errorMessage = error.body?.message || 
                           error.message || 
                           JiraIntegrationModal.ERROR_MESSAGES.UNEXPECTED_ERROR;
        
        this.addError(errorMessage);
        
        this.showToast(
            'Error',
            'Failed to process Jira issues. Please check the details and try again.',
            'error'
        );
    }
    
    createMockResultData(result) {
        // Create mock stories data
        this.createdStories = [];
        for (let i = 0; i < result.storiesCreated; i++) {
            this.createdStories.push({
                id: `story-${i + 1}`,
                name: `Story ${i + 1} - Sample Story Name`,
                jiraKey: `${this.projectKey}-${i + 100}`
            });
        }
        
        // Create mock work items data
        this.createdWorkItems = [];
        for (let i = 0; i < result.workItemsCreated; i++) {
            this.createdWorkItems.push({
                id: `workitem-${i + 1}`,
                subject: `JIRA-${this.projectKey}-${i + 200}: Sample Work Item Subject`,
                jiraKey: `${this.projectKey}-${i + 200}`,
                parentStory: i < this.createdStories.length ? this.createdStories[i].jiraKey : null
            });
        }
    }
    
    addError(message) {
        if (message && !this.errorMessages.includes(message)) {
            this.errorMessages = [...this.errorMessages, message];
        }
    }
    
    clearErrors() {
        this.errorMessages = [];
    }
    
    focusOnProjectKeyInput() {
        // Focus on project key input after modal opens
        setTimeout(() => {
            const inputElement = this.template.querySelector('#project-key-input');
            if (inputElement) {
                inputElement.focus();
            }
        }, 100);
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }
}