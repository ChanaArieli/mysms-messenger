import { Component, signal, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth/auth.service';
import { MessageService } from '../../core/services/message.service';
import { ComposeBoxComponent } from './compose-box/compose-box.component';
import { MessageListComponent } from './message-list/message-list.component';

@Component({
  selector: 'app-messenger',
  standalone: true,
  imports: [CommonModule, ComposeBoxComponent, MessageListComponent],
  templateUrl: './messenger.component.html',
  styleUrls: ['./messenger.component.scss']
})
export class MessengerComponent {
  @ViewChild(ComposeBoxComponent) composeBox!: ComposeBoxComponent;
  @ViewChild(MessageListComponent) messageList!: MessageListComponent;

  apiError = signal<string | null>(null);
  currentUser!: any;

  constructor(
    private authService: AuthService,
    private messageService: MessageService,
    private router: Router
  ) {
    this.currentUser = this.authService.currentUser;
  }

  onMessageSent(data: { to: string; body: string }): void {
    this.apiError.set(null);

    try {
      this.messageService.sendMessage(data.to, data.body).subscribe({
        next: () => {
          try {
            if (this.messageList) {
              this.messageList.loadMessages();
            } else {
              console.warn('MessageListComponent not initialized');
            }
            if (this.composeBox) {
              this.composeBox.resetForm();
            } else {
              console.warn('ComposeBoxComponent not initialized');
            }
          } catch (err) {
            console.error('Error updating UI after message send:', err);
            this.apiError.set('Message sent but UI refresh failed');
          }
        },
        error: (err) => {
          let errorMsg = 'Failed to send message';

          if (err?.error?.errors) {
            if (Array.isArray(err.error.errors)) {
              errorMsg = err.error.errors[0];
            } else if (typeof err.error.errors === 'object') {
              errorMsg = err.error.errors.base || Object.values(err.error.errors)[0];
            }
          } else if (err?.error?.error) {
            errorMsg = err.error.error;
          }

          this.apiError.set(errorMsg);
          if (this.composeBox) {
            this.composeBox.isLoading.set(false);
          }
        }
      });
    } catch (err) {
      console.error('Error sending message:', err);
      this.apiError.set('An unexpected error occurred');
      if (this.composeBox) {
        this.composeBox.isLoading.set(false);
      }
    }
  }

  logout(): void {
    this.authService.logout().subscribe({
      next: () => {
        this.router.navigate(['/login']);
      }
    });
  }
}
