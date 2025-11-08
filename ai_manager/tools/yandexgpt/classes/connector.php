<?php
// This file is part of Moodle - http://moodle.org/
//
// Moodle is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Moodle is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Moodle.  If not, see <http://www.gnu.org/licenses/>.

namespace aitool_yandexgpt;

use local_ai_manager\local\prompt_response;
use local_ai_manager\local\unit;
use local_ai_manager\local\usage;
use local_ai_manager\request_options;
use Psr\Http\Message\StreamInterface;

/**
 * Connector for YandexGPT.
 *
 * @package    aitool_yandexgpt
 * @license    http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */
class connector extends \local_ai_manager\base_connector {

    #[\Override]
    protected function set_url(): void {
        $this->apiurl = 'https://llm.api.cloud.yandex.net/foundationModels/v1/completion';
    }

    #[\Override]
    protected function set_headers(): void {
        $this->headers = [
            'Content-Type' => 'application/json',
            // Using the API Key from instance settings.
            'Authorization' => 'Api-Key ' . $this->instance->get_apikey(),
        ];
    }

    #[\Override]
    public function get_models_by_purpose(): array {
        // Models available in YandexGPT.
        $textmodels = ['yandexgpt-lite', 'yandexgpt'];
        return [
            'chat' => $textmodels,
            'feedback' => $textmodels,
            'singleprompt' => $textmodels,
            'translate' => $textmodels,
            'questiongeneration' => $textmodels,
        ];
    }

    #[\Override]
    public function get_unit(): unit {
        return unit::TOKEN;
    }

    #[\Override]
    public function execute_prompt_completion(StreamInterface $result, request_options $requestoptions): prompt_response {
        $content = json_decode($result->getContents(), true);

        if (isset($content['error']) || !isset($content['result']['alternatives'][0]['message']['text'])) {
            $errormessage = $content['message'] ?? ($content['error']['message'] ?? 'Unknown error from YandexGPT API');
            throw new \moodle_exception('apierror', 'local_ai_manager', '', null, $errormessage);
        }

        $message = $content['result']['alternatives'][0]['message']['text'];
        $prompttokencount = (float) ($content['result']['usage']['inputTextTokens'] ?? 0.0);
        $responsetokencount = (float) ($content['result']['usage']['completionTokens'] ?? 0.0);
        $totaltokencount = (float) ($content['result']['usage']['totalTokens'] ?? 0.0);

        return prompt_response::create_from_result($this->instance->get_model(),
                new usage($totaltokencount, $prompttokencount, $responsetokencount),
                $message);
    }

    #[\Override]
    public function get_prompt_data(string $prompttext, request_options $requestoptions): array {
        $options = $requestoptions->get_options();
        $messages = [];

        if (array_key_exists('conversationcontext', $options)) {
            foreach ($options['conversationcontext'] as $message) {
                $role = match ($message['sender']) {
                    'user' => 'user',
                    'ai' => 'assistant',
                    default => continue 2,
                };
                $messages[] = ['role' => $role, 'text' => $message['message']];
            }
        }

        $messages[] = ['role' => 'user', 'text' => $prompttext];

        $data = [
            'modelUri' => 'gpt://' . $this->instance->get_catalog_id() . '/' . $this->instance->get_model(),
            'completionOptions' => [
                'stream' => false,
                'temperature' => $this->instance->get_temperature(),
                'maxTokens' => $requestoptions->get_max_tokens(),
            ],
            'messages' => $messages,
        ];

        return $data;
    }

    #[\Override]
    public function allowed_mimetypes(): array {
        return [];
    }
}