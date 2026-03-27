-- Initial schema for the training API database
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert sample data
INSERT INTO items (name, description) VALUES
    ('Item 1', 'First sample item'),
    ('Item 2', 'Second sample item'),
    ('Item 3', 'Third sample item');
