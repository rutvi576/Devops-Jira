import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import processJiraIssues from '@salesforce/apex/JiraService.processJiraSubtasks';
import getStoriesWithWorkItems from '@salesforce/apex/JiraStoryController.getStoriesWithWorkItems';
import getProjectJiraKey from '@salesforce/apex/JiraStoryController.getProjectJiraKey';
import { CurrentPageReference } from 'lightning/navigation';

export default class JiraStoryWorkItemCreator extends NavigationMixin(LightningElement) {
    @track isLoading = false;
    @track showResults = false;
    @track processingResult = {};
    @track storiesWithWorkItems = [];
    @track accordionSections = [];
    @track error;
    @track projectKey = null;
    @track createdStoryIds = [];

    wireRecordId;
    currectRecordId;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            console.log('currentPageReference: ', JSON.stringify(currentPageReference));
            this.wireRecordId = currentPageReference.state.recordId;
        }
    }

    @api set recordId(value) {
        this.currectRecordId = value;
        console.log('this.currectRecordId: ', this.currectRecordId);
    }

    get recordId() {
        return this.currectRecordId;
    }

    async connectedCallback() {
        await this.initializeComponent();
    }

    async initializeComponent() {
        if (!this.wireRecordId && !this.currectRecordId) {
            this.error = 'No record ID provided';
            this.showToast('Error', 'Record ID is required', 'error');
            console.error('No record ID provided');
            return;
        }

        this.isLoading = true;
        
        try {
            // Fetch Project Key
            this.projectKey = await getProjectJiraKey({ recordId: this.wireRecordId || this.currectRecordId });
            console.log('Fetched projectKey: ', this.projectKey);
            
            if (!this.projectKey) {
                this.error = 'No Jira Project Key found';
                this.showToast('Error', 'Jira Project Key is not configured', 'error');
                console.error('No Jira Project Key found');
                this.isLoading = false;
                return;
            }

            await this.handleProcessJiraIssues();
            
        } catch (error) {
            console.error('Error initializing component: ', error);
            this.error = error.body ? error.body.message : error.message;
            this.showToast('Error', 'Failed to initialize: ' + this.error, 'error');
            this.isLoading = false;
        }
    }

    async handleProcessJiraIssues() {
        if (!this.projectKey) {
            this.error = 'Project key is not available';
            this.showToast('Error', 'Project key is required', 'error');
            console.error('Project key is not available');
            return;
        }

        this.isLoading = true;
        this.error = null;
        this.createdStoryIds = [];

        try {
            console.log('Calling processJiraIssues with projectKey: ', this.projectKey);
            const result = await processJiraIssues({ projectKey: this.projectKey });
            console.log('Raw processJiraIssues result: ', result);
            
            if (!result) {
                throw new Error('processJiraIssues returned null or undefined');
            }

            this.processingResult = { ...result };
            console.log('Processing result assigned: ', JSON.stringify(this.processingResult));
            
            this.createdStoryIds = result.storyIds ? [...result.storyIds] : [];
            console.log('Created story IDs: ', JSON.stringify(this.createdStoryIds));
            
            if (result.errors && result.errors.length > 0) {
                this.error = result.errors.join(', ');
                this.showToast('Error', this.error, 'error');
                console.error('Errors in processing result: ', this.error);
            } else {
                const message = `Created ${result.storiesCreated || 0} stories and ${result.workItemsCreated || 0} work items`;
                this.showToast('Success', message, 'success');
                console.log('Success message: ', message);
                
                if (this.createdStoryIds.length > 0) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    await this.fetchStoriesWithWorkItems();
                } else {
                    console.warn('No story IDs returned');
                    this.showToast('Warning', 'No stories were created', 'warning');
                }
            }
            
        } catch (error) {
            console.error('Error processing Jira issues: ', error);
            this.error = error.body ? error.body.message : error.message;
            this.showToast('Error', 'Failed to process Jira issues: ' + this.error, 'error');
        } finally {
            this.isLoading = false;
            this.showResults = true;
        }
    }

    async fetchStoriesWithWorkItems() {
        try {
            console.log('Fetching stories with IDs: ', JSON.stringify(this.createdStoryIds));
            const stories = await getStoriesWithWorkItems({ storyIds: this.createdStoryIds });
            console.log('Fetched stories: ', JSON.stringify(stories));
            this.storiesWithWorkItems = stories || [];
            console.log('storiesWithWorkItems: ', JSON.stringify(this.storiesWithWorkItems));
            this.prepareAccordionData();
        } catch (error) {
            console.error('Error fetching stories: ', error);
            this.showToast('Error', 'Failed to fetch stories: ' + (error.body ? error.body.message : error.message), 'error');
            this.storiesWithWorkItems = [];
        }
    }

    prepareAccordionData() {
        console.log('Preparing accordion data: ', JSON.stringify(this.storiesWithWorkItems));
        this.accordionSections = this.storiesWithWorkItems.map(story => {
            const completionPercentage = story.Completion_Percentage__c || 0;
            const progressData = this.calculateProgressData(completionPercentage);
            
            return {
                id: story.Id,
                name: story.Id,
                label: `${story.Name} (${story.Work_Items__r ? story.Work_Items__r.length : 0} Work Items)`,
                isExpanded: false,
                workItems: (story.Work_Items__r || []).map(workItem => ({
                    ...workItem
                })),
                jiraTicketKey: story.Jira_Ticket_Key__c,
                completionPercentage: completionPercentage,
                progressBarStyle: progressData.progressBarStyle,
                progressFillStyle: progressData.progressFillStyle,
                progressStatus: progressData.progressStatus,
                progressBadgeClass: progressData.progressBadgeClass
            };
        });
        console.log('Accordion sections: ', JSON.stringify(this.accordionSections));
    }

    calculateProgressData(percentage) {
        const normalizedPercentage = Math.max(0, Math.min(100, percentage || 0));
        
        let fillColor, progressStatus, badgeClass;
        
        if (normalizedPercentage === 0) {
            fillColor = '#e0e5ee';
            progressStatus = 'Not Started';
            badgeClass = 'slds-badge';
        } else if (normalizedPercentage < 25) {
            fillColor = '#fe9339';
            progressStatus = 'Just Started';
            badgeClass = 'slds-badge_warning';
        } else if (normalizedPercentage < 50) {
            fillColor = '#ffb75d';
            progressStatus = 'In Progress';
            badgeClass = 'slds-badge_success';
        } else if (normalizedPercentage < 75) {
            fillColor = '#1589ee';
            progressStatus = 'Making Progress';
            badgeClass = 'slds-badge_success';
        } else if (normalizedPercentage < 100) {
            fillColor = '#4bca81';
            progressStatus = 'Almost Done';
            badgeClass = 'slds-badge_success';
        } else {
            fillColor = '#2e844a';
            progressStatus = 'Completed';
            badgeClass = 'slds-badge_success';
        }

        return {
            progressBarStyle: 'background-color: #f3f3f3; border-radius: 6px; overflow: hidden; position: relative;',
            progressFillStyle: `width: ${normalizedPercentage}%; background: linear-gradient(90deg, ${fillColor} 0%, ${this.lightenColor(fillColor, 20)} 100%); transition: width 0.3s ease-in-out;`,
            progressStatus: progressStatus,
            progressBadgeClass: badgeClass
        };
    }

    lightenColor(color, percent) {
        const hex = color.replace('#', '');
        const r = parseInt(hex.substr(0, 2), 16);
        const g = parseInt(hex.substr(2, 2), 16);
        const b = parseInt(hex.substr(4, 2), 16);

        const newR = Math.min(255, Math.floor(r + (255 - r) * (percent / 100)));
        const newG = Math.min(255, Math.floor(g + (255 - g) * (percent / 100)));
        const newB = Math.min(255, Math.floor(b + (255 - b) * (percent / 100)));

        return `#${newR.toString(16).padStart(2, '0')}${newG.toString(16).padStart(2, '0')}${newB.toString(16).padStart(2, '0')}`;
    }

    handleStoryLinkClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        this.navigateToRecord(recordId, 'Jira_Story__c');
    }

    handleWorkItemLinkClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        this.navigateToRecord(recordId, 'sf_devops__Work_Item__c');
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: objectApiName,
                actionName: 'view'
            }
        });
    }

    handleRefresh() {
        this.initializeComponent();
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    get hasResults() {
        return this.showResults && !this.isLoading;
    }

    get hasError() {
        return this.error && !this.isLoading;
    }

    get hasStories() {
        if (!this.storiesWithWorkItems || this.storiesWithWorkItems.length === 0) {
            console.log('No stories to display');
            return false;
        }
        return true;
    }

    get summaryMessage() {
        if (this.processingResult && (this.processingResult.storiesCreated || this.processingResult.workItemsCreated)) {
            return `Created ${this.processingResult.storiesCreated || 0} stories and ${this.processingResult.workItemsCreated || 0} work items`;
        }
        return 'No records created';
    }

    get currentProjectKey() {
        return this.projectKey || 'Not loaded';
    }
}