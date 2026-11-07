/*
 * aegis-auth — the Aegis lock screen's PAM verifier.
 *
 * A tiny setuid-root helper: reads the candidate password from stdin
 * (the shell handles masking), verifies it against the requested user
 * through PAM service "aegis-auth" (pam_unix — the same module the
 * greeter uses), and prints OK or FAIL. Swaylock's model, minimum size.
 *
 *   usage: echo "$PASS" | aegis-auth <username>
 *   exit 0 + "OK"   on success
 *   exit 1 + "FAIL" otherwise
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <pwd.h>
#include <security/pam_appl.h>

static const char *g_password = NULL;

static int converse(int num_msg, const struct pam_message **msg,
                    struct pam_response **resp, void *appdata_ptr)
{
    (void)msg;
    (void)appdata_ptr;
    if (num_msg <= 0 || g_password == NULL)
        return PAM_CONV_ERR;
    struct pam_response *r = calloc((size_t)num_msg, sizeof(struct pam_response));
    if (!r)
        return PAM_CONV_ERR;
    for (int i = 0; i < num_msg; ++i) {
        r[i].resp = strdup(g_password);
        r[i].resp_retcode = 0;
    }
    *resp = r;
    return PAM_SUCCESS;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: aegis-auth <username>\n");
        return 2;
    }

    char buf[512];
    if (!fgets(buf, sizeof(buf), stdin))
        return 2;
    buf[strcspn(buf, "\r\n")] = '\0';
    g_password = buf;

    struct passwd *pw = getpwnam(argv[1]);
    if (!pw) {
        printf("FAIL\n");
        return 1;
    }

    struct pam_conv conv = { converse, NULL };
    pam_handle_t *pamh = NULL;
    int ret = pam_start("aegis-auth", pw->pw_name, &conv, &pamh);
    if (ret != PAM_SUCCESS) {
        printf("FAIL\n");
        return 1;
    }
    ret = pam_authenticate(pamh, 0);
    if (ret == PAM_SUCCESS)
        ret = pam_acct_mgmt(pamh, 0);
    pam_end(pamh, ret);

    if (ret == PAM_SUCCESS) {
        printf("OK\n");
        return 0;
    }
    printf("FAIL\n");
    return 1;
}
