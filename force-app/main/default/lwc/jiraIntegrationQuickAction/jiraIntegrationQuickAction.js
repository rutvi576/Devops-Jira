// jiraIntegrationQuickAction.js
import { LightningElement, api } from 'lwc';

export default class JiraIntegrationQuickAction extends LightningElement {
     @api recordId;
    modalOpened = false;

    handleOpenModal() {
        const modalComponent = this.template.querySelector('c-jira-integration-modal');
        if (modalComponent) {
            try {
                modalComponent.openModal();
                this.modalOpened = true;
            } catch (error) {
                console.error('Error opening modal:', JSON.stringify(error));
            }
        } else {
            console.warn('Modal component not found');
        }
    }
}