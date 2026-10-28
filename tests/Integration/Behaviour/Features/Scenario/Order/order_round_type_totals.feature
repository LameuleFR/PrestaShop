# ./vendor/bin/behat -c tests/Integration/Behaviour/behat.yml -s order --tags order-round-type-totals
@restore-all-tables-before-feature
@clear-cache-before-feature
@order-round-type-totals
Feature: Orders created in BO follow the rounding type and add up to the amount paid
  As a merchant
  I want the order totals to follow the configured rounding type
  So that the orders add up to the amount the customer paid

  # first_product and second_product cost 8.334 tax excluded, i.e. 8.83404 tax included,
  # third_product costs 3.337 tax excluded, i.e. 3.53722 tax included (6% tax):
  # rounding each article, each line or the cart total gives different results.
  Background:
    Given email sending is disabled
    And the current currency is "USD"
    And country "US" is enabled
    And the module "dummy_payment" is installed
    And I am logged in as "test@prestashop.com" employee
    And there is customer "testCustomer" with email "pub@prestashop.com"
    And customer "testCustomer" has address in "US" country
    And there is a zone "north_america" named "North America"
    And I add new tax "us-tax" with following properties:
      | name       | US Tax (6%) |
      | rate       | 6           |
      | is_enabled | true        |
    And I add the tax rule group "us-tax-group" for the tax "us-tax" with the following conditions:
      | name    | US Tax (6%) |
      | country | US          |
    And I create carrier "first_carrier" with specified properties:
      | name             | First carrier |
      | active           | true          |
      | shippingMethod   | price         |
      | zones            | north_america |
      | shippingHandling | false         |
    And I set ranges for carrier "first_carrier" with specified properties for all shops:
      | id_zone       | range_from | range_to | range_price |
      | north_america | 0          | 1000     | 5           |
    And I set tax rule "us-tax-group" for carrier "first_carrier"
    And I create carrier "second_carrier" with specified properties:
      | name             | Second carrier |
      | active           | true           |
      | shippingMethod   | price          |
      | zones            | north_america  |
      | shippingHandling | false          |
    And I set ranges for carrier "second_carrier" with specified properties for all shops:
      | id_zone       | range_from | range_to | range_price |
      | north_america | 0          | 1000     | 10          |
    And I set tax rule "us-tax-group" for carrier "second_carrier"
    And I add product "first_product" with following information:
      | name[en-US] | first product |
      | type        | standard      |
    And I update product "first_product" with following values:
      | price           | 8.334       |
      | tax rules group | US Tax (6%) |
      | active          | true        |
    And I update product "first_product" stock with following information:
      | delta_quantity | 50 |
    And I assign product first_product with following carriers:
      | first_carrier |
    And I add product "second_product" with following information:
      | name[en-US] | second product |
      | type        | standard       |
    And I update product "second_product" with following values:
      | price           | 8.334       |
      | tax rules group | US Tax (6%) |
      | active          | true        |
    And I update product "second_product" stock with following information:
      | delta_quantity | 50 |
    And I assign product second_product with following carriers:
      | second_carrier |
    And I add product "third_product" with following information:
      | name[en-US] | third product |
      | type        | standard      |
    And I update product "third_product" with following values:
      | price           | 3.337       |
      | tax rules group | US Tax (6%) |
      | active          | true        |
    And I update product "third_product" stock with following information:
      | delta_quantity | 50 |
    And I assign product third_product with following carriers:
      | first_carrier |

  Scenario Outline: Order created in BO with several lines and a taxed carrier, rounding <rounding type>
    Given specific shop configuration for "rounding type" is set to round <rounding type>
    And I create an empty cart "dummy_cart" for customer "testCustomer"
    And I select "US" address as delivery and invoice address for customer "testCustomer" in cart "dummy_cart"
    And I add 1 products "first product" to the cart "dummy_cart"
    And I add 6 products "third product" to the cart "dummy_cart"
    And I select carrier "first_carrier" for cart "dummy_cart"
    When I add order "bo_order1" with the following details:
      | cart                | dummy_cart       |
      | message             | test             |
      | payment module name | dummy_payment    |
      | status              | Payment accepted |
    Then order "bo_order1" should have following details:
      | total_products           | <products tax excl> |
      | total_products_wt        | <products tax incl> |
      | total_discounts_tax_excl | 0.00                |
      | total_discounts_tax_incl | 0.00                |
      | total_shipping_tax_excl  | 5.00                |
      | total_shipping_tax_incl  | 5.30                |
      | total_paid_tax_excl      | <total tax excl>    |
      | total_paid_tax_incl      | <total tax incl>    |
      | total_paid               | <total tax incl>    |
      | total_paid_real          | <total tax incl>    |
    And order "bo_order1" has status "Payment accepted"

    Examples:
      | rounding type | products tax excl | products tax incl | total tax excl | total tax incl |
      | each article  | 28.37             | 30.07             | 33.37          | 35.37          |
      | each line     | 28.35             | 30.05             | 33.35          | 35.35          |
      | cart total    | 28.36             | 30.06             | 33.36          | 35.36          |

  Scenario Outline: Orders split by carrier add up to the amount paid, rounding <rounding type>
    Given specific shop configuration for "rounding type" is set to round <rounding type>
    And I create an empty cart "dummy_cart" for customer "testCustomer"
    And I select "US" address as delivery and invoice address for customer "testCustomer" in cart "dummy_cart"
    And I add 1 products "first product" to the cart "dummy_cart"
    And I add 1 products "second product" to the cart "dummy_cart"
    When I add order "bo_order1" with the following details:
      | cart                | dummy_cart       |
      | message             | test             |
      | payment module name | dummy_payment    |
      | status              | Payment accepted |
    Then order "bo_order1" should be split into 2 orders with following summed details:
      | total_products          | <products tax excl> |
      | total_products_wt       | <products tax incl> |
      | total_paid_tax_excl     | <total tax excl>    |
      | total_paid_tax_incl     | <total tax incl>    |
      | total_paid              | <total tax incl>    |
      | total_paid_real         | <total tax incl>    |

    Examples:
      | rounding type | products tax excl | products tax incl | total tax excl | total tax incl |
      | each article  | 16.66             | 17.66             | 31.66          | 33.56          |
      | each line     | 16.66             | 17.66             | 31.66          | 33.56          |
