# M02 Test Plan

## A. Regression

1. Open an existing editable local project.
2. Open Hello3E v1.0.0, increment the counter and close it.
3. Reopen Hello3E and confirm the counter is unchanged.
4. Install Hello3E v1.1.0 and confirm the counter remains.

## B. Add a remote web app

1. Open `Applications`.
2. Tap `+` then `Add app from the Internet`.
3. Enter an HTTPS website.
4. Tap `Fetch website data`.
5. Confirm that the name, description or icon is filled when the website exposes them.
6. Change any of these fields manually and save.
7. Confirm the card is marked `Internet` and shows the connection status.

## C. Navigation protection

1. Add a site with `Same site only`.
2. Open it and tap a link to another domain.
3. Confirm the external link opens in the system browser instead of replacing the app page.
4. Add a second app with `Declared domains` and confirm declared subdomains remain inside 3ELocal.

## D. Offline and errors

1. Open a remote app, then enable Airplane Mode.
2. Confirm the offline screen appears.
3. Disable Airplane Mode and reopen or reload the app.
4. Open an invalid or unavailable URL and confirm a readable error banner appears.

## E. Details and persistence

1. Open the information button on a card.
2. Confirm type, size, install date, update date, last launch and launch count.
3. Sign in to a remote website, close 3ELocal and reopen it.
4. On iOS 17+, confirm the remote app session persists and is isolated from another remote app.

## F. Files app intake

1. From Files, share a `.3eweb` file to 3ELocal while the 3E folder is connected.
2. Confirm it installs.
3. Disconnect the 3E folder, share another `.3eweb`, then reconnect the folder.
4. Confirm the pending package installs automatically.
