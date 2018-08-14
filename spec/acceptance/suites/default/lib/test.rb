require_relative('./util')

include TlogTestUtil

local_ssh('127.0.0.1', 2222, 'root', 'Test passw0rd @f some l3ngth')

