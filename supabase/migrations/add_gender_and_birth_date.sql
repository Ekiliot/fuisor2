-- Add gender and birth_date fields to profiles table
-- Gender: TEXT, optional (can be 'male', 'female', 'secret', or NULL)
-- Birth date: DATE, required (month and year only, day will be set to 1)

-- First add the column as nullable with default
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS gender TEXT CHECK (gender IN ('male', 'female', 'secret') OR gender IS NULL);

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS birth_date DATE DEFAULT '2000-01-01';

-- Update existing rows to have default birth_date
UPDATE profiles SET birth_date = '2000-01-01' WHERE birth_date IS NULL;

-- Now make birth_date NOT NULL
ALTER TABLE profiles 
ALTER COLUMN birth_date SET NOT NULL;

-- Add comment
COMMENT ON COLUMN profiles.gender IS 'User gender: male, female, secret, or NULL';
COMMENT ON COLUMN profiles.birth_date IS 'User birth date (month and year, day set to 1)';

