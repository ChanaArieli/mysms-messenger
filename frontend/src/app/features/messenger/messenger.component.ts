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
  @ViewChild(MessageListComponent) messageList!: MessageListComponent;

  currentUser = this.authService.currentUser;
  isLoading = signal(false);

  constructor(
    private authService: AuthService,
    private messageService: MessageService,
    private router: Router
  ) {}

  onMessageSent(data: { to: string; body: string }): void {
    this.isLoading.set(true);
    this.messageService.sendMessage(data.to, data.body).subscribe({
      next: () => {
        this.isLoading.set(false);
        if (this.messageList) {
          this.messageList.loadMessages();
        }
      },
      error: (err) => {
        this.isLoading.set(false);
      }
    });
  }

  logout(): void {
    this.authService.logout().subscribe({
      next: () => {
        this.router.navigate(['/login']);
      }
    });
  }
}
