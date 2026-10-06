# Deployment Guide - MySMS Messenger

## Quick Start - Deploy to Render.com

This guide walks you through deploying MySMS Messenger to Render.com for a live demo.

### Prerequisites

1. **GitHub Repository**: Code must be pushed to https://github.com/ChanaArieli/mysms-messenger
2. **MongoDB Atlas Account**: For cloud MongoDB database
   - Create a free cluster at https://www.mongodb.com/cloud/atlas
   - Get your MongoDB URI (connection string)
3. **Twilio Account**: With verified phone number
   - Account SID and Auth Token from https://www.twilio.com/console
4. **Render.com Account**: https://render.com (free tier available)

### Step 1: Push Code to GitHub

```bash
# Fix git authentication issue by using a Personal Access Token
git remote set-url origin https://YOUR_GITHUB_USERNAME:YOUR_PAT@github.com/ChanaArieli/mysms-messenger.git
git push origin main
```

**Alternative**: If using SSH, ensure your GitHub SSH key is added to your account:
```bash
# Add SSH key to GitHub: https://github.com/settings/keys
ssh-add ~/.ssh/id_ed25519
git remote set-url origin git@github.com:ChanaArieli/mysms-messenger.git
git push origin main
```

### Step 2: Set Up MongoDB Atlas

1. Create a free MongoDB cluster
2. Create a database user with credentials
3. Get your connection URI: `mongodb+srv://username:password@cluster.mongodb.net/mysms_prod`

### Step 3: Deploy to Render.com

1. Go to https://render.com and sign up/login
2. Click **New +** → **Web Service**
3. Connect your GitHub repository (ChanaArieli/mysms-messenger)
4. Configure the service:
   - **Name**: `mysms-messenger`
   - **Root Directory**: (leave empty)
   - **Environment**: Docker
   - **Branch**: `main`
   - **Build Command**: (use default)
   - **Start Command**: (use default)

### Step 4: Set Environment Variables

In Render dashboard, add these environment variables:

```
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_FROM_NUMBER=+1234567890
MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/mysms_prod
DEVISE_JWT_SECRET_KEY=your-secret-key-change-this
FRONTEND_ORIGIN=https://mysms-messenger.onrender.com
RAILS_ENV=production
```

### Step 5: Configure Twilio Webhooks (Optional)

For real-time delivery status updates:

1. In Render dashboard, copy your app URL (e.g., `https://mysms-messenger.onrender.com`)
2. Go to Twilio Console → Messaging → Services (or Messaging Settings)
3. Set **Status Callback URL** to: `https://mysms-messenger.onrender.com/webhooks/twilio/status`

### Step 6: Deploy

1. Render will automatically build and deploy when you connect your GitHub repo
2. Monitor deployment progress in the Render dashboard
3. Once deployed, your app will be live at: `https://mysms-messenger.onrender.com`

## Testing Your Deployment

1. Visit `https://mysms-messenger.onrender.com`
2. Create a new account with email and password
3. Verify your phone number in Twilio (free trial limitation)
4. Send a test SMS

## Troubleshooting

### Build Fails: "Cannot find module"
- Ensure `Gemfile.lock` and `package-lock.json` are committed to git

### App Starts but Shows 502 Error
- Check Logs tab in Render dashboard
- Verify MONGODB_URI is correct
- Ensure Twilio credentials are set

### Frontend Not Loading
- Check that Angular build is working: `npm run build` in `frontend/` directory
- Verify `Dockerfile.production` has correct build output path

### Can't Send SMS
- Verify Twilio credentials are correct
- Check phone number is verified in Twilio (for free trial)
- View logs to see Twilio API errors

## Architecture

The app is deployed as a single Docker container containing:

1. **Frontend**: Built Angular app served from Rails public directory
2. **Backend**: Rails API handling authentication and SMS
3. **Database**: MongoDB Atlas (cloud-hosted)

```
Browser → Render.com (Rails API + Angular Frontend)
              ↓
          Rails Server (port 3000)
              ├── Serves Angular assets
              ├── Handles API routes (/login, /signup, /messages)
              └── Calls Twilio API
                    ↓
              MongoDB Atlas (database)
                    ↓
              Twilio (SMS)
```

## Production Considerations

### Current Implementation
- ✅ Deployed on Render.com free tier
- ✅ Single-process Rails server
- ✅ Static assets served by Rails
- ✅ MongoDB Atlas for data persistence

### Future Improvements for Scale
- Use CDN (Cloudflare, AWS CloudFront) for static assets
- Implement caching (Redis)
- Separate API and static servers
- Add monitoring and error tracking (Sentry)
- Implement rate limiting on SMS API
- Add health checks and auto-scaling

## Costs

- **Render.com**: Free tier (limited to 750 hours/month)
- **MongoDB Atlas**: Free tier (512MB storage)
- **Twilio**: Pay per SMS sent (~$0.0075 per SMS)

**Estimated monthly cost** (with moderate usage): $5-20

## More Information

- [Render Documentation](https://render.com/docs)
- [MongoDB Atlas Guide](https://docs.atlas.mongodb.com/)
- [Rails API Deployment](https://guides.rubyonrails.org/api_app.html)
- [Angular Deployment](https://angular.io/guide/deployment)
