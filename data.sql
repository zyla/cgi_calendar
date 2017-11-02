INSERT INTO users (login,password,full_name,user_type) VALUES ('szef', 'hunter2', 'Krzysztof Jarzyna', 'boss');
INSERT INTO users (login,password,full_name,user_type) VALUES ('jan', '123', 'Jan Kowalski', 'empl');

INSERT INTO calendar_entries(user_login, entry_type, date_from, date_to) VALUES
  ('szef', 'work', '2017-11-02 09:00', '2017-11-02 15:00'),
  ('szef', 'work', '2017-11-03 09:00', '2017-11-03 14:00'),

  ('jan', 'work', '2017-11-02 07:00', '2017-11-02 22:00'),
  ('jan', 'work', '2017-11-03 07:00', '2017-11-03 22:00'),

  (null, 'meeting', '2017-11-03 11:00', '2017-11-03 13:00')
  ;
