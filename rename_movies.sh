#!/bin/bash

set -e

source vars.env

# Get Library items
plex_section_tag="all"

function echoerr() { echo "$@" 1>&2; }

function get_tmdbid(){
  if [[ "$id" == "tmdb"* ]] || [[ "$id" == "imdb"* ]] || [[ "$id" == "tvdb"* ]]; then
    # Ignore IMDB and TVDB
    if [[ "$id" == "tmdb"* ]]; then
      tmdbid=$( printf "$id" | sed 's|tmdb://||' )
    fi
  else
    echoerr "ID found that is not TMDB, IMDB, or TVDB"
  fi
}

function rename_item(){
  local file_new_name="$1"
  if [ "${test,,}" == "false" ]; then
    mv "$file_path/$file_name" "$file_path/$file_new_name" "$mv_flags"
  else
    echo "$file_path/$file_name -> $file_path/$file_new_name"
  fi
}

function process_library(){
  local plex_section_id=$1
  metadata_all=$( curl --silent --request GET \
    --url "$plex_server_protocol://$plex_server_address:$plex_server_port/library/sections/$plex_section_id/$plex_section_tag" \
    --header "X-Plex-Token: $x_plex_token" \
    --header "Accept: application/json" | jq '[.MediaContainer.Metadata[] | {ratingKey}]' )

  metadata_all_length=$( printf "$metadata_all" | jq length )

  # Get metadata for item
  for ((i = 0 ; i < $metadata_all_length ; i++ )); do
    plex_rating_key=$( printf "$metadata_all" | jq --raw-output ".[$i].ratingKey" )
    if [ "$plex_type" == "movie" ]; then
      metadata=$( curl --silent --request GET \
      --url "$plex_server_protocol://$plex_server_address:$plex_server_port/library/metadata/$plex_rating_key" \
      --header "X-Plex-Token: $x_plex_token" \
      --header "Accept: application/json" | jq '[.MediaContainer.Metadata[] | {year, Guid, Media, title}]' )
    elif [ "$plex_type" == "show" ]; then
      metadata=$( curl --silent --request GET \
      --url "$plex_server_protocol://$plex_server_address:$plex_server_port/library/metadata/$plex_rating_key" \
      --header "X-Plex-Token: $x_plex_token" \
      --header "Accept: application/json" | jq '[.MediaContainer.Metadata[] | {year, Guid, Location, title}]' )
    fi
    length=$( printf "$metadata" | jq length )
    if [ $length -eq 1 ]; then
      title=$( printf "$metadata" | jq --raw-output '.[0].title'  )
      # Check if Guids exists
      guid=$( printf "$metadata" | jq --raw-output '.[0].Guid' )
      if [ "$guid" != "null" ]; then
        # Iterate over Guids
        while read -r id; do
          get_tmdbid
        done < <(printf "$guid" | jq --raw-output '.[].id')

        # Get year
        year=$( printf "$metadata" | jq --raw-output '.[0].year' )
        if ! [ "$year" == "null" ]; then
          # Get paths
          if [ "$plex_type" == "movie" ]; then
            media=$( printf "$metadata" | jq '.[0].Media' )
          elif [ "$plex_type" == "show" ]; then
            media=$( printf "$metadata" | jq '.[0].Location' )
          fi
          length=$( printf "$media" | jq length )
          if [ $length -eq 1 ]; then
            # Check length of parts
            if [ "$plex_type" == "movie" ]; then
              part=$( printf "$media" | jq '.[0].Part' )
              length=$( printf "$part" | jq length )
            elif [ "$plex_type" == "show" ]; then
              part=$( printf "$media" | jq --raw-output '.[0].path' )
              # Allows to pass length test
              length=$( echo "1" )
            fi
            if [ $length -eq 1 ]; then
              if [ "$plex_type" == "movie" ]; then
                file_full_path=$( printf "$part" | jq --raw-output '.[0].file' | sed "s|$plex_media_path|$media_path|")
              elif [ "$plex_type" == "show" ]; then
                file_full_path=$( printf "$part" | sed "s|$plex_media_path|$media_path|")
              fi
              file_path=$( dirname "$file_full_path" )
              file_name=$( basename "$file_full_path" )
              if [ "$plex_type" == "movie" ]; then
                file_ext=${file_name##*.}
                file_name="${file_name%.*}"
              fi

              directory_name=$( dirname "$file_path" )
              if ! [[ "${directory_name,,}" == "${file_path}" ]]; then
                file_new_name="$file_name"
                # Check if year exists in file name
                file_year=$( echo "$file_name" | grep -o -P '(?<=\()[0-9]{4}(?=\))' || true)
                if [ -z "$file_year" ] || [[ "$file_year" =~ ^[0-9]{4}$ ]]; then
                  if [ -z "$file_year" ] || [ "$year" == "$file_year" ]; then
                    # Check if file name year matches
                    if [[ "$file_name" != *"($year)"* ]]; then
                      file_new_name="$file_new_name ($year)"
                    fi

                    # Check if TMDBID exists in file name
                    # TODO Verify another TMDBID does not exist
                    if [[ "$file_name" != *"[tmdbid-$tmdbid]"* ]]; then
                      file_new_name="$file_new_name [tmdbid-$tmdbid]"
                    fi

                    if [ "$plex_type" == "movie" ]; then
                      file_new_name="$file_new_name.$file_ext"
                    fi

                    rename_item "$file_new_name"
                  else
                    echoerr "Different year in metadata than in filename"
                  fi
                else
                  echoerr "Multiple Years detected for $plex_rating_key: $title"
                fi
              else
                echoerr "Need to rename dir: $file_path"
              fi
            else
              echoerr "Part length is not 1. Part length is $length for $plex_rating_key: $title"
            fi
          else
            echoerr "Media length is not 1. Media length is $length for $plex_rating_key: $title"
          fi 
        else
          echoerr "Year is null for $plex_rating_key: $title"
        fi
      else
        echoerr "GUID does not exist for $plex_rating_key: $title"
      fi
    else
      echoerr "Length of Metadata is greater not 1. Length is $length for $plex_rating_key"
    fi
  done
}

function process_libraries(){
  all_libraries=$( curl --silent --request GET \
  --url "$plex_server_protocol://$plex_server_address:$plex_server_port/library/sections" \
  --header "X-Plex-Token: $x_plex_token" \
  --header "Accept: application/json" | jq )

  # echo "$all_libraries" | jq
  library_length=$( printf "$all_libraries" | jq --raw-output '.MediaContainer.size' )
  for ((library_index = 0 ; library_index < $library_length ; library_index++ )); do
    plex_section_id=$( echo "$all_libraries" | jq --raw-output ".MediaContainer.Directory[$library_index].key" )
    plex_type=$( echo "$all_libraries" | jq --raw-output ".MediaContainer.Directory[$library_index].type" )
    if [ "$plex_type" == "movie" ] || [ "$plex_type" == "show" ]; then
      process_library $plex_section_id
    else
      echoerr "Unknown library type. Plex Section ID: $plex_section_id. Plex Type is $plex_type"
    fi
  done
}

process_libraries
