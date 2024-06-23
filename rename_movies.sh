#!/bin/bash

set -e

source vars.env

# Get Library items
plex_section_id="$plex_section_id_movies"
plex_section_tag="all"

echoerr() { echo "$@" 1>&2; }

metadata_all=$( curl --silent --request GET \
  --url "$plex_server_protocol://$plex_server_address:$plex_server_port/library/sections/$plex_section_id/$plex_section_tag" \
  --header "X-Plex-Token: $x_plex_token" \
  --header "Accept: application/json" | jq '[.MediaContainer.Metadata[] | {ratingKey}]' )

metadata_all_length=$( printf "$metadata_all" | jq length )

# Get metadata for item
for ((i = 0 ; i < $metadata_all_length ; i++ )); do
    plex_rating_key=$( printf "$metadata_all" | jq --raw-output ".[$i].ratingKey" )
    metadata=$( curl --silent --request GET \
      --url "$plex_server_protocol://$plex_server_address:$plex_server_port/library/metadata/$plex_rating_key" \
      --header "X-Plex-Token: $x_plex_token" \
      --header "Accept: application/json" | jq '[.MediaContainer.Metadata[] | {year, Guid, Media, title}]' )

    length=$( printf "$metadata" | jq length )
    if [ $length -eq 1 ]; then
        title=$( printf "$metadata" | jq --raw-output '.[0].title'  )
        # Check if Guids exists
        guid=$( printf "$metadata" | jq --raw-output '.[0].Guid' )
        if [ "$guid" != "null" ]; then
            # Iterate over Guids
            while read -r id; do
                if [[ "$id" == "tmdb"* ]] || [[ "$id" == "imdb"* ]] || [[ "$id" == "tvdb"* ]]; then
                    # Ignore IMDB and TVDB
                    if [[ "$id" == "tmdb"* ]]; then
                        tmdbid=$( printf "$id" | sed 's|tmdb://||' )
                    fi
                else
                    echoerr "ID found that is not TMDB, IMDB, or TVDB"
                fi
            done < <(printf "$guid" | jq --raw-output '.[].id')
        else
            echoerr "GUID does not exist for $plex_rating_key: $title"
            continue
        fi

        # Get year
        year=$( printf "$metadata" | jq --raw-output '.[0].year' )
        if [ "$year" == "null" ]; then
            echoerr "Year is null for $plex_rating_key: $title"
            continue
        fi

        # Get paths
        media=$( printf "$metadata" | jq '.[0].Media' )
        length=$( printf "$media" | jq length )
        if [ $length -eq 1 ]; then
            # Check length of parts
            part=$( printf "$media" | jq '.[0].Part' )
            length=$( printf "$part" | jq length )
            if [ $length -eq 1 ]; then
                file_full_path=$( printf "$part" | jq --raw-output '.[0].file' | sed "s|$plex_media_path|$media_path|")
                file_path=$( dirname "$file_full_path" )
                file_name=$( basename "$file_full_path" )
                directory_name=$( dirname "$file_path" )
                if [[ "${directory_name,,}" == "${file_path}" ]]; then
                    echoerr "Need to rename dir: $file_path"
                    continue
                fi
                file_name_wo_ext="${file_name%.*}"
                file_ext=${file_name##*.}

                file_new_name="$file_name_wo_ext"
                # Check if year exists in file name
                if [[ "$file_name_wo_ext" != *"($year)"* ]]; then
                    file_new_name="$file_new_name ($year)"
                fi

                # Check if TMDBID exists in file name
                if [[ "$file_name_wo_ext" != *"[tmdbid-$tmdbid]"* ]]; then
                    file_new_name="$file_new_name [tmdbid-$tmdbid]"
                fi
                file_new_name="$file_new_name.$file_ext"
                if [ "${test,,}" == "false" ]; then
                    mv "$file_path/$file_name" "$file_path/$file_new_name" "$mv_flags"
                else
                    echo "$file_path/$file_name -> $file_path/$file_new_name"
                fi
            else
                echoerr "Part length is not 1. Part length is $length for $plex_rating_key: $title"
            fi
        else
            echoerr "Media length is not 1. Media length is $length for $plex_rating_key: $title"
        fi 
    else
        echoerr "Length of Metadata is greater not 1. Length is $length for $plex_rating_key"
    fi
done
