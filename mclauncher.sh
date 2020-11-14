#!/bin/sh

#
# param file
# param file_sha1sum
# param file_size
# param file_url
#
download_file() {
	file="$1"
	file_sha1sum="$2"
	file_size="$3"
	file_url="$4"

	[ -z "$file" ] \
		&& echo "file given, but empty!" >&2 \
		&& exit 1

	[ -z "$file_sha1sum" ] \
		&& echo "file_sha1sum given, but empty!" >&2 \
		&& exit 1

	[ -z "$file_size" ] \
		&& echo "file_size given, but empty!" >&2 \
		&& exit 1

	[ -z "$file_url" ] \
		&& echo "file_url given, but empty!" >&2 \
		&& exit 1

	[ $# -ne 4 ] \
		&& echo "download_file takes 4 parameter, given $#!" >&2 \
		&& exit 1

	mkdir -p "${file%/*}"
	[ -e "$file" ] \
		|| (
			curl "$file_url" > "$file"
			sha1sum=$(sha1sum "$file" \
				| cut -d' ' -f1) \
				|| exit 1

			size=$(du -b "$file" \
				| cut -d'	' -f1) \
				|| exit 1

			[ "$file_sha1sum" != "$sha1sum" ] \
				&& rm "$file" \
				&& echo "SHA1 does not match" \
				&& exit 1

			[ "$file_size" -ne "$size" ] \
				&& rm "$file" \
				&& echo "Size does not match" \
				&& exit 1
		)
}


#
# param json_url
#
extract_libraries() {
	json_url="$1"

	[ -z "$json_url" ] \
		&& echo "json_url given, but empty!" >&2 \
		&& exit 1

	[ $# -ne 1 ] \
		&& echo "extract_libraries takes 1 parameter, given $#!" >&2 \
		&& exit 1


	curl "$json_url" \
		| jq -r '.libraries[].downloads.artifact | map(.) | @tsv' \
		| while read file file_sha1sum file_size file_url; do
			download_file \
				"libraries/$file" \
				"$file_sha1sum" \
				"$file_size" \
				"$file_url"
		done

	curl "$json_url" \
		| jq -r '.libraries[].downloads.classifiers."natives-linux" // []
			| map(.) | @tsv' \
		| while read file file_sha1sum file_size file_url; do
			download_file \
				"libraries/$file" \
				"$file_sha1sum" \
				"$file_size" \
				"$file_url"
		done
}

#
# param email
# param password
# return
# 	accessToken username uuid 
#
login() {
	authserver="https://authserver.mojang.com"

	email="$1"
	password="$2"

	[ -z "$login" ] \
		&& echo "login given, but empty!" >&2 \
		&& exit 1
		
	[ -z "$password" ] \
		&& echo "password given, but empty!" >&2 \
		&& exit 1

	[ $# -ne 2 ] \
		&& echo "login takes 2 parameters, given $#!" >&2 \
		&& exit 1


	curl \
		--header "Content-Type: application/json" \
		--request POST \
		--data "{
			\"agent\":{\"name\":\"Minecraft\",\"version\":1},
			\"username\":\"$email\",
			\"password\":\"$password\"
		}" "$authserver/authenticate" \
		| jq -r '[.accessToken,.selectedProfile.name,.selectedProfile.id]|@tsv'
}


#
# return
# 	id url
#
chose_version() {
	versions="https://launchermeta.mojang.com/mc/game/version_manifest.json"
	curl "$versions" \
		| jq -r '.versions[] | .id' \
		| dmenu -l 20
}

#
# param json_url
#
download_client() {
	json_url="$1"

	[ -z "$json_url" ] \
		&& echo "json_url given, but empty!" >&2 \
		&& exit 1

	[ $# -ne 1 ] \
		&& echo "download_client takes 1 parameter, given $#!" >&2 \
		&& exit 1
	
	curl "$json_url" \
		| jq -r '.downloads.client | map(.) | @tsv' \
		| {
		read -r sha1sum size url

		download_file "./client.jar" "$sha1sum" "$size" "$url"
	}
}

#
# param id
# param name
# param directory
#
create_instance() {
	versions="https://launchermeta.mojang.com/mc/game/version_manifest.json"

	id="$1"
	name="$2"
	directory="$3"
	instance_path="$directory"

	[ -z "$id" ] \
		&& echo "id given, but empty!" >&2 \
		&& exit 1
		
	[ -z "$name" ] \
		&& echo "name given, but empty!" >&2 \
		&& exit 1

	[ -z "$directory" ] \
		&& echo "directory given, but empty!" >&2 \
		&& exit 1

	[ $# -ne 3 ] \
		&& echo "create_instance takes 3 parameters, given $#!" >&2 \
		&& exit 1

	json_url=$(curl "$versions" \
		| jq -r ".versions[] | [.id,.url] | @tsv" \
		| grep "$id\s" \
		| cut -d"	" -f2) \
		|| exit 1

	mkdir -p "$directory"/"$name"
	starting_directory="$PWD"
	cd "$directory"/"$name"

	extract_libraries "$json_url"
	download_client "$json_url"

	cd "$starting_directory"
}


launch_instance() {
	name="$1"
	directory="$2"

	[ -z "$name" ] \
		&& echo "name given, but empty!" >&2 \
		&& exit 1

	[ -z "$directory" ] \
		&& echo "directory given, but empty!" >&2 \
		&& exit 1

	[ $# -ne 2 ] \
		&& echo "launch_instance takes 2 parameters, given $#!" >&2 \
		&& exit 1

	starting_directory="$PWD"
	cd "$directory"/"$name"

	cp=$(find "$PWD/libraries" -type f \
		| paste -s -d: -)

	java \
		-Djava.library.path=/tmp \
		-Dminecraft.launcher.brand=mclauncher.sh \
		-Dminecraft.launcher.version=1.0 \
		-cp "$cp:$PWD/client.jar" \
		-Xmx4096m \
		-Xms4096m \
		-Dminecraft.applet.TargetDirectory="$PWD/" \
		-Dfml.ignorePatchDiscrepancies=true \
		-Dfml.ignoreInvalidMinecraftCertificates=true \
		-Xms256m \
		net.minecraft.client.main.Main \
		--width 854 \
		--height 480 \
		--username Lukasz210 \
		--version 1.16.4 \
		--gameDir "$PWD" \
		--assetsDir ~/.minecraft/assets \
		--assetIndex 1.16 \
		--uuid 8f9591def8234d1f9279cd6e83ad3f9b \
		--accessToken "access token, the long one" \
		--userType mojang \
		--versionType release

	cd "$starting_directory"
}


login="$1"
instance="new_instance"

stty -echo
printf 'Password: '
read password
stty echo

version=$(chose_version) \
	|| exit 1


create_instance "$version" "$instance" "." \
	|| exit 1

credentials=$(login "$login" "$password") \
	|| exit 1

launch_instance "$instance" "." \
	|| exit 1
