import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Message } from '../models/message.model';

@Injectable({ providedIn: 'root' })
export class MessageService {
  constructor(private http: HttpClient) {}

  getMessages() {
    return this.http.get<Message[]>(`/messages`);
  }

  sendMessage(to: string, body: string) {
    return this.http.post<Message>(`/messages`, {
      message: { to, body }
    });
  }
}
