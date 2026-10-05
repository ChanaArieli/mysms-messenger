import { Injectable, signal } from '@angular/core';
import { HttpClient, HttpResponse } from '@angular/common/http';
import { TokenStorageService } from './token-storage.service';
import { User } from '../models/user.model';
import { tap } from 'rxjs/operators';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly apiUrl = 'http://localhost:3000';
  currentUser = signal<User | null>(null);
  isLoggedIn = signal(false);

  constructor(
    private http: HttpClient,
    private tokenStorage: TokenStorageService
  ) {
    this.checkToken();
  }

  signup(email: string, password: string) {
    return this.http.post<{ user: User }>(
      `${this.apiUrl}/signup`,
      { user: { email, password, password_confirmation: password } },
      { observe: 'response' }
    ).pipe(
      tap(res => {
        if (res.body?.user) {
          this.currentUser.set(res.body.user);
          this.isLoggedIn.set(true);
        }
        const token = res.headers.get('authorization')?.replace('Bearer ', '');
        if (token) this.tokenStorage.setToken(token);
      })
    );
  }

  login(email: string, password: string) {
    return this.http.post<{ user: User }>(
      `${this.apiUrl}/login`,
      { user: { email, password } },
      { observe: 'response' }
    ).pipe(
      tap(res => {
        if (res.body?.user) {
          this.currentUser.set(res.body.user);
          this.isLoggedIn.set(true);
        }
        const token = res.headers.get('authorization')?.replace('Bearer ', '');
        if (token) this.tokenStorage.setToken(token);
      })
    );
  }

  logout() {
    return this.http.delete(`${this.apiUrl}/logout`).pipe(
      tap(() => {
        this.currentUser.set(null);
        this.isLoggedIn.set(false);
        this.tokenStorage.clearToken();
      })
    );
  }

  private checkToken(): void {
    const token = this.tokenStorage.getToken();
    if (token) {
      this.isLoggedIn.set(true);
    }
  }
}
