import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Message } from '../models/message.model';

@Injectable({ providedIn: 'root' })
export class MessageService {
  private readonly apiUrl = 'http://localhost:3000';

  constructor(private http: HttpClient) {}

  getMessages() {
    return this.http.get<Message[]>(`${this.apiUrl}/messages`);
  }

  sendMessage(to: string, body: string) {
    return this.http.post<Message>(`${this.apiUrl}/messages`, {
      message: { to, body }
    });
  }
}
