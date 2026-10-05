import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Message } from '../../../core/models/message.model';

@Component({
  selector: 'app-message-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './message-card.component.html',
  styleUrls: ['./message-card.component.scss']
})
export class MessageCardComponent {
  @Input() message!: Message;

  getStatusColor(): string {
    switch (this.message.status) {
      case 'delivered':
        return 'delivered';
      case 'sent':
        return 'sent';
      case 'failed':
      case 'undelivered':
        return 'failed';
      default:
        return 'queued';
    }
  }

  getStatusText(): string {
    return this.message.status.charAt(0).toUpperCase() + this.message.status.slice(1);
  }
}
