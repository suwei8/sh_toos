


# Download and install nvm:
curl -o- https://gh-proxy.555606.xyz/https://raw.githubusercontent.com/suwei8/sh_toos/refs/heads/main/Node/install.sh | bash

# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"

# Download and install Node.js:
nvm install 22

# Verify the Node.js version:
node -v # Should print "v22.20.0".

# Verify npm version:
npm -v # Should print "10.9.3".
