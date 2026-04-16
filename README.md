# macwolf

A simple macOS menubar application to send Wake-on-LAN magic packets to preconfigured interfaces.

## Building the Application

To build the application from source, follow these steps:

1. **Build with Swift Package Manager**:
   ```bash
   swift build -c release
   ```

2. **Create the App Bundle structure**:
   ```bash
   mkdir -p macwolf.app/Contents/MacOS
   ```

3. **Move the binary and Info.plist into the bundle**:
   ```bash
   cp .build/release/macwolf macwolf.app/Contents/MacOS/
   cp Info.plist macwolf.app/Contents/
   ```

4. **Run the application**:
   You can now open `macwolf.app` from Finder or run it via terminal:
   ```bash
   open macwolf.app
   ```

## Running Tests

```bash
swift test
```
