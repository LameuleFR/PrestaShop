<?php
/**
 * For the full copyright and license information, please view the
 * docs/licenses/LICENSE.txt file that was distributed with this source code.
 */

declare(strict_types=1);

namespace Tests\Integration\Adapter\MailTemplate;

use PHPUnit\Framework\TestCase;
use PrestaShop\PrestaShop\Adapter\MailTemplate\MailPartialTemplateRenderer;
use PrestaShop\PrestaShop\Core\Language\LanguageInterface;

class OrderConfProductListPartialTest extends TestCase
{
    /**
     * @dataProvider provideTemplates
     */
    public function testUnitAndTotalPricesAreRenderedInTheirOwnColumn(string $templateName): void
    {
        global $smarty;

        $language = $this->createMock(LanguageInterface::class);
        $language->method('getIsoCode')->willReturn('en');

        $content = (new MailPartialTemplateRenderer($smarty))->render($templateName, $language, [[
            'reference' => 'REF-1',
            'name' => 'Mug',
            'unit_price' => 'UNIT-1.75',
            'price' => 'TOTAL-3.50',
            'quantity' => 2,
            'customization' => [],
        ]]);

        $this->assertSame(1, substr_count($content, 'UNIT-1.75'));
        $this->assertSame(1, substr_count($content, 'TOTAL-3.50'));
        $this->assertLessThan(strpos($content, 'TOTAL-3.50'), strpos($content, 'UNIT-1.75'));
    }

    public static function provideTemplates(): iterable
    {
        yield 'html' => ['order_conf_product_list.tpl'];
        yield 'text' => ['order_conf_product_list.txt'];
    }
}
