import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth/auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.scss']
})
export class LoginComponent {
  email = '';
  password = '';
  confirmPassword = '';
  isLogin = true;
  isLoading = signal(false);
  error = signal('');

  constructor(
    private authService: AuthService,
    private router: Router
  ) {}

  toggleMode() {
    this.isLogin = !this.isLogin;
    this.error.set('');
  }

  onSubmit() {
    if (!this.email || !this.password) {
      this.error.set('Email and password are required');
      return;
    }

    if (!this.isLogin && this.password !== this.confirmPassword) {
      this.error.set('Passwords do not match');
      return;
    }

    this.isLoading.set(true);
    const request = this.isLogin
      ? this.authService.login(this.email, this.password)
      : this.authService.signup(this.email, this.password);

    request.subscribe({
      next: () => {
        this.router.navigate(['/']);
      },
      error: (err) => {
        const errors = err.error?.errors;
        if (errors) {
          if (typeof errors === 'object') {
            const errorMessages = Object.entries(errors)
              .map(([, message]) => message)
              .flat()
              .join(', ');
            this.error.set(errorMessages);
          } else {
            this.error.set(errors);
          }
        } else {
          this.error.set('Authentication failed');
        }
        this.isLoading.set(false);
      }
    });
  }
}
