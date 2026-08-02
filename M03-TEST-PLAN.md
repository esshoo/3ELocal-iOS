# 3ELocal M03 Test Plan — Online Packages and Private Catalog

## 1. Upgrade safety

1. Install M03 over the working M02 build using the same Bundle ID.
2. Confirm local projects still appear and open.
3. Confirm installed `.3eweb` apps and remote web apps remain available.
4. Open Hello3E and confirm its saved counter still exists.

## 2. Direct HTTPS package download

1. Open **Downloads**.
2. Press `+` and paste a public HTTPS link ending in `.3eweb`.
3. Confirm progress appears.
4. When ready, press **Inspect and Install**.
5. Confirm the package passes the existing package validator before installation.

## 3. Pause, resume, cancel and retry

Use a package large enough to keep the download active for several seconds.

1. Start a download and press **Pause**.
2. Press **Resume** and confirm progress continues.
3. Start another download and press **Cancel**.
4. Press **Retry** after a failed or cancelled download.
5. Close and reopen 3ELocal after a completed download; the downloaded file should still appear as ready to install.

> Some servers do not support HTTP byte ranges. In that case iOS may restart a paused download from the beginning instead of continuing from the exact byte.

## 4. QR installation

1. Open the direct download form.
2. Press **Scan QR** and allow camera access.
3. Scan a QR code containing a direct public HTTPS `.3eweb` URL.
4. Confirm the URL is inserted and the package downloads normally.

## 5. Private catalog

Upload the complete `TestCatalog` folder to a public HTTPS location. For a public GitHub repository, a Raw URL can be used for `catalog.json`.

1. Open **Store**.
2. Enter the HTTPS URL of `catalog.json`.
3. Press **Check apps and updates**.
4. Confirm `Hello 3E 1.2.0` appears with its icon and description.
5. Confirm relative icon and package links resolve from the catalog location.

## 6. Update comparison and data preservation

Starting with Hello3E 1.1.0 installed:

1. Set its counter to a recognizable number.
2. Load the M03 test catalog.
3. Confirm the app card and Store show update `1.2.0`.
4. Download and install the update.
5. Confirm the app now shows `1.2.0` and the counter is unchanged.
6. Test rollback to the previous version and confirm the data remains.

## 7. Ignore one version

1. When update 1.2.0 is shown, choose **Ignore this version**.
2. Confirm the update badge disappears for that app.
3. In the Store choose **Show it** to restore the update.
4. A later catalog version must appear even if 1.2.0 was previously ignored.

## 8. Deep links

Test these URL forms with percent-encoded HTTPS values:

```text
localweb://install?url=https%3A%2F%2Fexample.com%2FApp.3eweb
localweb://catalog?url=https%3A%2F%2Fexample.com%2Fcatalog.json
```

The first should start a package download. The second should save and load the catalog.

## Pass condition

M03 passes when existing M02 data remains intact, direct and catalog downloads work, packages are still validated before installation, update comparison is correct, ignored versions persist, and Hello3E data survives the 1.2.0 update.
