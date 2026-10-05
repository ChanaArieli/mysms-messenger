import { Component, OnInit, signal, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MessageService } from '../../../core/services/message.service';
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
  private pollInterval: any;

  constructor(private messageService: MessageService) {}

  ngOnInit(): void {
    this.loadMessages();
    this.startPolling();
  }

  ngOnDestroy(): void {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
    }
  }

  loadMessages(): void {
    this.isLoading.set(true);
    this.messageService.getMessages().subscribe({
      next: (data) => {
        this.messages.set(data);
        this.isLoading.set(false);
      },
      error: (err) => {
        this.error.set('Failed to load messages');
        this.isLoading.set(false);
      }
    });
  }

  private startPolling(): void {
    this.pollInterval = setInterval(() => {
      this.loadMessages();
    }, 5000);
  }

  refresh(): void {
    this.loadMessages();
  }
}
