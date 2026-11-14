These files not use by CSS files.

"ui-icon.png"     is embedded "tools/js/src/adiary.js" in base64 format.
"error-close.gif" is embedded "pub/assets/theme/base.css" in base64 format.

ui-icon.png
  adiary.js changes the icon color to the theme color (#ui-icon-autoload).
  It must be a 2-color palette PNG. After editing, run:
    perl t/tools/make_ui_icon.pl
  (the top-left pixel color is the background. Draw icons in one color)
