# Vespera Firefox Configuration

## What's Included

This configuration merges the best settings from Aurora and Bazzite:

- **WebRender GPU acceleration** (from Aurora)
- **Hardware video decoding** (from both)
- **ML/AI features disabled** (from Bazzite)
- **userChrome.css support enabled** (Vespera addition)

## Custom CSS Styling

We've enabled `userChrome.css` support, which allows you to customize Firefox's UI.

### How to Use userChrome.css

1. **Find your Firefox profile directory:**
   ```bash
   cd ~/.mozilla/firefox/*.default-release/
   ```

2. **Create the chrome directory:**
   ```bash
   mkdir -p chrome
   cd chrome
   ```

3. **Create userChrome.css:**
   ```bash
   nano userChrome.css
   ```

4. **Add your CSS rules:**
   ```css
   /* Example: Hide titlebar spacer (recommended by Vespera) */
   .titlebar-spacer {
       display: none !important;
   }

   /* Add more custom CSS here */
   ```

5. **Restart Firefox** to see changes

### Recommended CSS

```css
/* Hide titlebar spacer for cleaner look */
.titlebar-spacer {
    display: none !important;
}
```

## Upstream Sources

This configuration is manually tracked from:
- [Aurora Firefox Config](https://github.com/get-aurora-dev/common/blob/main/system_files/shared/usr/share/ublue-os/firefox-config/01-aurora-global.js)
- [Bazzite Firefox Config](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/share/ublue-os/firefox-config/01-bazzite-global.js)

Check these links periodically for upstream changes.
