symlinks:
	for i in /var/lib/jenkins/jobs/*; do [ -d "$i/workspace/webapp" ] && ln -snf "$i/workspace/webapp" "`basename "$i"`"; done

clean:
	find . -maxdepth 1 -type l | xargs -r rm -v
