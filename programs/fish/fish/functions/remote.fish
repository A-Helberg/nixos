function remote
    set remote_dir $PWD

    # Escape the directory path to handle spaces and special characters
    set escaped_remote_dir (string escape -- $remote_dir)

    # Build the remote command
    set remote_command "cd $escaped_remote_dir; $argv"

    ssh -t 10.253.0.1 $remote_command
end
