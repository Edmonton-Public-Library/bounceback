# copies most rescent files from eplapp for updating to git.
#SERVER=edpl-t.library.ualberta.ca
SERVER=eplapp.library.ualberta.ca
USER=sirsi
REMOTE=~/Unicorn/EPLwork/anisbet/
LOCAL=~/projects/bounceback/
APP=bounceback.pl

put:
	perl -c ${LOCAL}${APP}
	scp ${LOCAL}${APP} ${USER}@${SERVER}:${REMOTE}
get:
	scp ${USER}@${SERVER}:${REMOTE}${APP} ${LOCAL}
test:
	perl -c ${LOCAL}${APP}
