import argparse
import os


def parse_env_file(file_path):
    """Parse .env file into a dictionary."""
    env_vars = {}
    current_section = None

    if not os.path.exists(file_path):
        return env_vars

    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#'):
                current_section = line.lstrip('#').strip()
                env_vars[current_section] = {}
            elif line and '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                if current_section:
                    env_vars[current_section][key] = value
                else:
                    env_vars[key] = value
    return env_vars


def write_env_file(env_vars, output_path):
    """Write dictionary to .env file."""
    with open(output_path, 'w', encoding='utf-8') as f:
        for section, vars_dict in env_vars.items():
            if isinstance(vars_dict, dict):
                f.write(f'#{section}\n')
                for key, value in vars_dict.items():
                    f.write(f'{key}={value}\n')
            else:
                f.write(f'{section}={vars_dict}\n')
            f.write('\n')


def merge_env_files(original_path, template_path, output_path):
    """Merge original .env with template, updating flags."""
    original = parse_env_file(original_path)
    template = parse_env_file(template_path)

    # Copy original
    result = original.copy()

    # Add missing variables from template
    for section, vars_dict in template.items():
        if section not in result:
            result[section] = {}
        if isinstance(vars_dict, dict):
            for key, value in vars_dict.items():
                if key not in result[section]:
                    result[section][key] = value

    # Update flags section with template values
    if 'flags' in template:
        result['flags'] = template['flags'].copy()

    write_env_file(result, output_path)
    print(f"Generated .env file at {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Merge .env files with template")
    parser.add_argument("--original", required=True, help="Path to original .env file")
    parser.add_argument("--template", required=True, help="Path to template .env file")
    parser.add_argument("--output", required=True, help="Path to output .env file")

    args = parser.parse_args()

    merge_env_files(args.original, args.template, args.output)