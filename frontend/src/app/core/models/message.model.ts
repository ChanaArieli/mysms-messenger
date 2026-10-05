export interface Message {
  id: string;
  to: string;
  body: string;
  status: 'queued' | 'sent' | 'delivered' | 'failed' | 'undelivered';
  error_message?: string;
  created_at: string;
}
