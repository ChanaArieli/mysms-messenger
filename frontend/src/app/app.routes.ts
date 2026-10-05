import { Routes } from '@angular/router';
import { LoginComponent } from './features/login/login.component';
import { MessengerComponent } from './features/messenger/messenger.component';
import { authGuard } from './core/auth/auth.guard';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  { path: '', component: MessengerComponent, canActivate: [authGuard] },
  { path: '**', redirectTo: '' }
];
