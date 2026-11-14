# Localizing Shotput

Shotput ships in English and Russian. Adding a language takes one folder.

## How it works

Every string the interface shows goes through `L(...)`:

```swift
Text(L("Show a preview"))
NSMenuItem(title: L("Check for Updates…"), action: nil, keyEquivalent: "")
```

The key is the English text itself, and the translation is a line in
`Resources/<language>.lproj/Localizable.strings`:

```
"Show a preview" = "Показывать превью";
```

There is no English translation file. A key with no entry falls back to the key, which is already
the English string, so:

- a new string works the moment it is written, in English, with no extra file to update;
- a half-translated language is a working language, with the missing parts in English;
- a translation that outlives its string is reported by the checker instead of silently rotting.

## Adding a language

1. Copy an existing translation folder and name it after the language code:

   ```bash
   cp -R Resources/ru.lproj Resources/de.lproj
   ```

2. Translate the values in `Resources/de.lproj/Localizable.strings`. Keep the keys exactly as
   they are: they are what the code asks for.

3. Add the code to `CFBundleLocalizations` in `Resources/Info.plist`:

   ```xml
   <string>de</string>
   ```

4. Check and build:

   ```bash
   ./Scripts/check-localization.py --strict
   SHOTPUT_SIGN_IDENTITY=- ./Scripts/build.sh
   ```

`Scripts/build.sh` copies every `*.lproj` into the app bundle, so nothing else needs changing.
macOS picks the translation when the system language matches; the app has no language setting of
its own.

## Working on a translation

```bash
Scripts/check-localization.py            # what is missing, what is stale, what is broken
Scripts/check-localization.py --missing  # untranslated keys as ready-to-fill entries
Scripts/check-localization.py --strict   # fail on missing and stale keys; CI runs this
```

The checker fails on things that would show the wrong thing at run time: duplicate keys, empty
values, and placeholders that were lost in translation (`%d` becoming nothing, `%@` becoming `%s`).
It is Python 3, which comes with the Command Line Tools you already need to build the app.

To see a translation without changing the system language:

```bash
open build/Shotput.app --args -AppleLanguages "(ru)"
```

The offscreen renders show the interface in one language too, which is how the screenshots in
`docs/` are made:

```bash
swift run shotput-dev settings /tmp/settings-ru.png -AppleLanguages "(ru)"
```

## Style

- Keep the voice of the English: short, plain, no exclamation marks, no marketing.
- Translate meaning, not words. "Capture area" is an instruction, so Russian gets an imperative.
- Leave proper names and file formats alone: Shotput, macOS, PNG, HEVC.
- Use the same term for the same thing everywhere. `docs/glossary.md` holds the picked terms.
- Punctuation follows the language: Russian uses «ёлочки», a comma before «что», and no
  title case in headings.
