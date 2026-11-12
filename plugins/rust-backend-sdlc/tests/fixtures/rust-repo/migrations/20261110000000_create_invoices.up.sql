CREATE TABLE invoices (
    id UUID NOT NULL,
    number TEXT NOT NULL,
    customer TEXT NOT NULL,
    amount_cents BIGINT NOT NULL,
    CONSTRAINT invoices_pkey PRIMARY KEY (id),
    CONSTRAINT invoices_number_key UNIQUE (number),
    CONSTRAINT invoices_number_check
        CHECK (char_length(number) BETWEEN 1 AND 64),
    CONSTRAINT invoices_customer_check
        CHECK (char_length(customer) BETWEEN 1 AND 255),
    CONSTRAINT invoices_amount_cents_check
        CHECK (amount_cents >= 0)
);
