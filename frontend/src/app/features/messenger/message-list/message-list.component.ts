import { Component, OnInit, signal, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { MessageService } from '../../../core/services/message.service';
import { AuthService } from '../../../core/auth/auth.service';
import { MessageCardComponent } from '../message-card/message-card.component';
import { Message } from '../../../core/models/message.model';

@Component({
  selector: 'app-message-list',
  standalone: true,
  imports: [CommonModule, MessageCardComponent],
  templateUrl: './message-list.component.html',
  styleUrls: ['./message-list.component.scss']
})
export class MessageListComponent implements OnInit {
  messages = signal<Message[]>([]);
  isLoading = signal(false);
  error = signal('');

  constructor(
    private messageService: MessageService,
    private authService: AuthService,
    private router: Router
  ) {}

  ngOnInit(): void {
    this.loadMessages();
  }

  loadMessages(): void {
    this.isLoading.set(true);
    this.messageService.getMessages().subscribe({
      next: (data) => {
        this.messages.set(data);
        this.isLoading.set(false);
      },
      error: (err) => {
        this.isLoading.set(false);
        if (err.status === 401) {
          this.authService.currentUser.set(null);
          this.authService.isLoggedIn.set(false);
          this.router.navigate(['/login']);
        } else {
          this.error.set('Failed to load messages');
        }
      }
    });
  }

  refresh(): void {
    this.loadMessages();
  }
}
