CREATE TABLE users (
  login text not null primary key,
  password text not null,
  full_name text not null,
  user_type text not null -- 'boss' or 'employee'
);

CREATE TABLE calendar_entries (
  entry_id integer primary key autoincrement,
  user_login text,
    -- nullable, NULL means for everyone, only boss can edit
  entry_type text not null,
    -- 'work', 'absence', 'vacation', 'meeting'
  date_from datetime not null,
  date_to datetime not null
);
