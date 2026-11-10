# Aegis OS — default interactive shell prompt.
#
# W11 — the accent prompt: #3E8BFF (the default accent token) on the ink
# terminal. The one-token accent system lives in Settings → Appearance;
# a static prompt colour is the deliberate compromise — bashrc is read
# before the shell session can consult tokens.conf.
case $- in
    *i*) ;;
      *) return ;;
esac

PS1='\[\e[38;2;62;139;255m\]\u@\h\[\e[0m\]:\[\e[38;2;62;139;255m\]\w\[\e[0m\]\$ '
