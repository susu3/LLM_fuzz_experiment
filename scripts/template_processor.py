#!/usr/bin/env python3
"""
模板处理器：解析YAML配置文件并生成Dockerfile和docker-compose文件
"""

import yaml
import argparse
import os
import sys
from pathlib import Path

def load_config(config_file):
    """加载YAML配置文件"""
    with open(config_file, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)

def process_dockerfile_template(config, tool_name, template_path, output_path):
    """处理Dockerfile模板"""
    with open(template_path, 'r') as f:
        template = f.read()
    
    target = config['target']
    tool_config = config['tools'][tool_name]
    
    # 替换模板变量
    replacements = {
        '{{base_image}}': target['build']['base_image'],
        '{{tool_name}}': tool_name,
        '{{target_name}}': target['name'],
        '{{tool_repo}}': tool_config['repo'],
        '{{target_source_path}}': target['source_path'],
        '{{target_dependencies}}': ' '.join(target['build'].get('dependencies', [])),
        '{{target_environment_vars}}': '\n'.join([f'ENV {var}' for var in target['build'].get('environment_vars', [])]),
        '{{target_pre_build_commands}}': '\n'.join([f'RUN {cmd}' for cmd in target['build'].get('pre_build_commands', [])]),
        '{{target_build_commands}}': '\n'.join([f'RUN {cmd}' for cmd in target['build'].get('build_commands', [])]),
        '{{target_post_build_commands}}': '\n'.join([f'RUN {cmd}' for cmd in target['build'].get('post_build_commands', [])]),
        '{{tool_build_commands}}': '\n'.join([f'RUN {cmd}' for cmd in tool_config.get('build_commands', [])]),
        '{{fuzz_command}}': tool_config['command']
    }
    
    # 进行替换
    result = template
    for placeholder, value in replacements.items():
        result = result.replace(placeholder, value)
    
    # 写入输出文件
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as f:
        f.write(result)
    
    print(f"生成Dockerfile: {output_path}")

def process_compose_template(config, template_path, output_path):
    """处理docker-compose模板"""
    with open(template_path, 'r') as f:
        template = f.read()
    
    target = config['target']
    tools = config['tools']
    
    # 生成services部分
    services_section = ""
    for tool_name in tools.keys():
        service_template = f"""  {tool_name}-{target['name']}:
    build:
      context: ../../
      dockerfile: dockerfiles/Dockerfile.{tool_name}.{target['name']}
    container_name: {tool_name}-{target['name']}
    restart: unless-stopped
    environment:
      - RUN_NUMBER=${{RUN_NUMBER:-1}}
      - HTTPS_PROXY=${{HTTPS_PROXY}}
      - LLM_API_KEY=${{LLM_API_KEY}}
    volumes:
      - ../../results:/opt/fuzzing/results
      - ../../logs:/opt/fuzzing/logs
      - {target['source_path']}:/opt/fuzzing/targets/{target['name']}:ro
    networks:
      - fuzzing-network
    command: /opt/fuzzing/run_24h.sh

"""
        services_section += service_template
    
    # 替换模板变量
    result = template.replace('{{#tools}}\n  {{tool_name}}-{{target_name}}:\n    build:\n      context: ../../\n      dockerfile: dockerfiles/Dockerfile.{{tool_name}}.{{target_name}}\n    container_name: {{tool_name}}-{{target_name}}\n    restart: unless-stopped\n    environment:\n      - RUN_NUMBER=${RUN_NUMBER:-1}\n      - HTTPS_PROXY=${HTTPS_PROXY}\n      - LLM_API_KEY=${LLM_API_KEY}\n    volumes:\n      - ../../results:/opt/fuzzing/results\n      - ../../logs:/opt/fuzzing/logs\n      - {{target_source_path}}:/opt/fuzzing/targets/{{target_name}}:ro\n    networks:\n      - fuzzing-network\n    command: /opt/fuzzing/run_24h.sh\n    \n{{/tools}}', services_section.rstrip())
    
    # 写入输出文件
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as f:
        f.write(result)
    
    print(f"生成docker-compose.yml: {output_path}")

def main():
    parser = argparse.ArgumentParser(description='模板处理器')
    parser.add_argument('--config', required=True, help='配置文件路径')
    parser.add_argument('--tool', help='工具名称（用于生成单个Dockerfile）')
    parser.add_argument('--template', help='模板文件路径')
    parser.add_argument('--output', help='输出文件路径')
    parser.add_argument('--type', choices=['dockerfile', 'compose'], default='dockerfile', help='模板类型')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.config):
        print(f"错误：配置文件不存在 {args.config}")
        sys.exit(1)
    
    config = load_config(args.config)
    
    if args.type == 'dockerfile':
        if not args.tool or not args.template or not args.output:
            print("错误：生成Dockerfile需要指定 --tool, --template, --output 参数")
            sys.exit(1)
        
        if args.tool not in config['tools']:
            print(f"错误：工具 {args.tool} 在配置文件中不存在")
            sys.exit(1)
        
        process_dockerfile_template(config, args.tool, args.template, args.output)
    
    elif args.type == 'compose':
        if not args.template or not args.output:
            print("错误：生成docker-compose需要指定 --template, --output 参数")
            sys.exit(1)
        
        process_compose_template(config, args.template, args.output)

if __name__ == '__main__':
    main()
