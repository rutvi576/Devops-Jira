import { LightningElement, track } from 'lwc';
import USER_MANUAL_DOCUMENT_LINK from '@salesforce/label/c.DevOpsFlow_Sync_UserGuide';
import SETUP_GUIDE_DOCUMENT_LINK from '@salesforce/label/c.DevOpsFlow_Sync_UserGuide';
import verifyJiraCredentials from '@salesforce/apex/JiraSetupConfiguration.verifyJiraCredentials';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ConfigurationSetup extends LightningElement {
    @track userName = '';
    @track apiKey = '';
    @track showSetupGuide = true;
    @track showUserGuide = false;
    @track showConnectJiraGuide = false;
    @track activeTab = 'setupGuide';
    @track isTransitioning = false;
    @track showSpinner = false;
    @track isClientIdVisible = false;
    @track isClientSecretVisible = false;
    @track userProfile = null; // Store user profile data
    @track errorMessage = ''; // Store error message

    drive_user_Manual_Document_Link = USER_MANUAL_DOCUMENT_LINK;
    setupGuide_manual_link = SETUP_GUIDE_DOCUMENT_LINK;

    // Getters for toggle icons
    get toggleIconClientId() {
        return this.isClientIdVisible ? 'utility:preview' : 'utility:hide';
    }
    get toggleIconClientSecret() {
        return this.isClientSecretVisible ? 'utility:preview' : 'utility:hide';
    }

    // Getters for input types
    get userNameType() {
        return this.isClientIdVisible ? 'text' : 'password';
    }
    get apiKeyType() {
        return this.isClientSecretVisible ? 'text' : 'password';
    }

    // Toggle visibility methods
    toggleUserNameVisibility() {
        this.isClientIdVisible = !this.isClientIdVisible;
    }
    toggleApiKeyVisibility() {
        this.isClientSecretVisible = !this.isClientSecretVisible;
    }

    // Handle input changes
    handleInputChange(event) {
        const { name, value } = event.target;
        this[name] = value.replace(/\s/g, '');
    }

    // Handle navigation
    handleNavigation(event) {
        const selectedItem = event.currentTarget.dataset.item;
        if (this.activeTab === selectedItem) return;

        this.isTransitioning = true;
        this.updateNavItems(selectedItem);

        setTimeout(() => {
            this.resetViews();
            this.updateView(selectedItem);
            this.activeTab = selectedItem;
            this.isTransitioning = false;
        }, 150);
    }

    // Update navigation item styles
    updateNavItems(selectedItem) {
        const navItems = this.template.querySelectorAll('.nav-item');
        navItems.forEach((item) => {
            item.classList.toggle('active', item.dataset.item === selectedItem);
        });
    }

    // Reset all views
    resetViews() {
        this.showSetupGuide = false;
        this.showUserGuide = false;
        this.showConnectJiraGuide = false;
    }

    // Update view based on selected item
    updateView(selectedItem) {
        switch (selectedItem) {
            case 'setupGuide':
                this.showSetupGuide = true;
                break;
            case 'userGuide':
                this.showUserGuide = true;
                break;
            case 'connectGoogleGuide':
                this.showConnectJiraGuide = true;
                break;
            default:
                console.error('Unknown navigation item:', selectedItem);
        }
    }

    // Verify Jira credentials
    async verifyCredentials() {
        if (!this.userName || !this.apiKey) {
            this.showToast('Error', 'Please enter both username and API key.', 'error');
            return;
        }

        this.showSpinner = true;
        this.userProfile = null;
        this.errorMessage = '';

        try {
            const result = await verifyJiraCredentials({
                username: this.userName,
                apiToken: this.apiKey
            });

            if (result.success) {
                this.userProfile = result.userProfile;
                this.showToast('Success', 'Jira credentials verified successfully!', 'success');
            } else {
                this.errorMessage = result.error;
                this.showToast('Error', result.error, 'error');
            }
        } catch (error) {
            this.errorMessage = 'Error verifying credentials: ' + error.message;
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.showSpinner = false;
        }
    }

    // Utility to show toast messages
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }
}