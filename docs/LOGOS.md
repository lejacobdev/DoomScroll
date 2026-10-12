# App logos in the picker

The "Choose your app" circles use each app's brand colour and a simple icon.
The official TikTok, Instagram, YouTube and Snapchat logos are trademarks and
aren't included in this repository, and App Review commonly rejects apps that
ship other companies' logos.

If you want the real logos for a build only you use, add them yourself:

1. In `Resources/iOS/Assets.xcassets`, add an image set named exactly:
   `Logo-tiktok`, `Logo-instagram`, `Logo-youtube`, `Logo-snapchat`, `Logo-web`.
2. Drop a square PNG (1024 px) into each. The app crops it to a circle.
3. Rebuild. Any missing image falls back to the default circle.

Don't push builds that include these to TestFlight external testing or the App
Store unless you have the rights to use them.
