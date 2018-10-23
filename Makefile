# copies most rescent files from eplapp for updating to git.
#SERVER=edpl-t.library.ualberta.ca
SERVER=eplapp.library.ualberta.ca
USER=sirsi
REMOTE=~/Unicorn/EPLwork/anisbet/Mail/
LOCAL=~/projects/bounceback/
APP=bounceback.pl
APP2=parsemail.pl
APP3=uniqbounce.pl
APP_DRIVER=mail.sh
.PHONEY: test put
put: test
	scp ${LOCAL}${APP} ${USER}@${SERVER}:${REMOTE}
	scp ${LOCAL}${APP2} ${USER}@${SERVER}:${REMOTE}
	scp ${LOCAL}${APP3} ${USER}@${SERVER}:${REMOTE}
	scp ${LOCAL}${APP_DRIVER} ${USER}@${SERVER}:${REMOTE}

test:
	perl -c ${LOCAL}${APP}
	perl -c ${LOCAL}${APP2}
	perl -c ${LOCAL}${APP3}
