csv_file=”/opt/Users.csv”
while IFS=”;” read -r firstName lastName role phone ou street zip city country password; do
if [ “$firstName” == “First Name” ]; then
		continue
fi
username=”${firstName,,}.${lastName,,}”
sudo samba-tool user add “$username” 123qweR%
done < “$csv_file”
