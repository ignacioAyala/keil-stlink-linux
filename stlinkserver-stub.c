/* ST's STLinkUSBDriver.dll launches stlinkserver.exe before connecting to it.
   The real server is stlink-tcp-bridge (native Linux), so this just exits. */
int main(void) { return 0; }
