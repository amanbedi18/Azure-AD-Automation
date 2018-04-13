CREATE USER [@sqladappname] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER @sqladappname;