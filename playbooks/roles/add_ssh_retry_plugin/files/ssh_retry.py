# This plugin retries failed ssh connections.

# This plugin has been accepted upstream into ansible v2, however until v2 is
# released we must carry the patch.

import time

import ansible.constants as C
from ansible.callbacks import vvv, display
from ansible.runner.connection_plugins import ssh as base_ssh


class Connection(base_ssh.Connection):
    '''SSH connections with retries on failure'''

    def exec_command(self, *args, **kwargs):
        """ Wrapper around _exec_command to retry in the case of an ssh
            failure

            Will retry if:
            * an exception is caught
            * ssh returns 255

            Will not retry if
            * remaining_tries is <2
            * retries limit reached
            """
        remaining_tries = C.get_config(
            C.p, 'ssh_retry', 'retries',
            'ANSIBLE_SSH_RETRY_RETRIES', 3, integer=True) + 1
        cmd_summary = "%s %s..." % (args[0], str(kwargs)[:200])
        for attempt in xrange(remaining_tries):
            pause = 2 ** attempt - 1
            if pause > 30:
                pause = 30
            time.sleep(pause)
            try:
                return_tuple = super(Connection, self).exec_command(*args,
                                                                    **kwargs)
            except Exception as e:
                msg = ("ssh_retry: attempt: %d, caught exception(%s) from cmd "
                       "(%s).") % (attempt, e, cmd_summary)
                display(msg, color='blue')
                if attempt == remaining_tries - 1:
                    raise e
                else:
                    continue
            # 0 = success
            # 1-254 = remote command return code
            # 255 = failure from the ssh command itself
            if return_tuple[0] != 255:
                break
            else:
                msg = ('ssh_retry: attempt: %d, ssh return code is 255. cmd '
                       '(%s).') % (attempt, cmd_summary)
                display(msg, color='blue')

        return return_tuple
