import { Component, Output, EventEmitter, Input, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-compose-box',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './compose-box.component.html',
  styleUrls: ['./compose-box.component.scss']
})
export class ComposeBoxComponent {
  @Output() messageSent = new EventEmitter<{ to: string; body: string }>();
  @Input() set apiError(value: string | null) {
    if (value) {
      this.error.set(value);
    }
  }

  to = '';
  body = '';
  isLoading = signal(false);
  error = signal('');

  onSend(): void {
    if (!this.to || !this.body) {
      this.error.set('Please fill in all fields');
      return;
    }

    this.isLoading.set(true);
    this.error.set('');

    this.messageSent.emit({ to: this.to, body: this.body });
    // Parent component will reset isLoading after API response
  }

  resetForm(): void {
    this.to = '';
    this.body = '';
    this.isLoading.set(false);
  }
}
