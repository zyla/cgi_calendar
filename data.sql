INSERT INTO users (login,password,full_name,user_type) VALUES ('szef', 'hunter2', 'Krzysztof Jarzyna', 'boss');
INSERT INTO users (login,password,full_name,user_type) VALUES ('jan', '123', 'Jan Kowalski', 'empl');

INSERT INTO calendar_entries(user_login, entry_type, date_from, date_to) VALUES
  ('szef', 'work', '2017-11-02T09:00:00', '2017-11-02T15:00:00'),
  ('szef', 'work', '2017-11-03T09:00:00', '2017-11-03T14:00:00'),

  ('jan', 'work', '2017-11-02T07:00:00', '2017-11-02T22:00:00'),
  ('jan', 'work', '2017-11-03T07:00:00', '2017-11-03T22:00:00')
  ;
